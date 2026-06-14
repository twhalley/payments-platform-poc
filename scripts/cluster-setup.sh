#!/usr/bin/env bash
# Bootstrap the kind cluster and deploy the core platform.
# Idempotent — safe to re-run. Deletes and recreates the cluster if it exists.
#
# Auto-detects the runtime environment:
#   GitHub Codespaces → plain kind (Docker via docker-in-docker feature)
#   Local             → sudo kind with rootful Podman
#
# Usage: bash scripts/cluster-setup.sh
#        make cluster
set -euo pipefail

# ── Environment detection ──────────────────────────────────────────────────────
if [[ "${CODESPACES:-}" == "true" ]]; then
  RUNTIME="GitHub Codespaces (Docker)"
  KIND_CONFIG="kind-config-codespaces.yaml"
  # In Codespaces, Docker is available without sudo via docker-in-docker feature
  run_kind() { kind "$@"; }
else
  RUNTIME="local (rootful Podman)"
  KIND_CONFIG="kind-config.yaml"
  # Locally, kind uses rootful Podman — see README § Local prerequisites
  run_kind() { sudo KIND_EXPERIMENTAL_PROVIDER=podman kind "$@"; }
fi

echo "==> Runtime: $RUNTIME"
echo "==> Kind config: $KIND_CONFIG"

# ── Cluster ───────────────────────────────────────────────────────────────────
echo "==> Creating kind cluster..."
if run_kind get clusters 2>/dev/null | grep -q "^payments-poc$"; then
  echo "    Cluster already exists — deleting and recreating..."
  run_kind delete cluster --name payments-poc
fi
run_kind create cluster --config "$KIND_CONFIG"

echo "==> Exporting kubeconfig..."
mkdir -p ~/.kube
run_kind get kubeconfig --name payments-poc > ~/.kube/config
chmod 600 ~/.kube/config
export KUBECONFIG=~/.kube/config

# ── CNI (Codespaces only) ─────────────────────────────────────────────────────
# The Codespaces kind config sets disableDefaultCNI: true because kind's built-in
# CNI installer runs kubectl *inside* the kind container, which fails with
# "connection refused on 6443" — hairpin NAT is not supported by the DinD bridge.
# Install Flannel from outside instead: kubectl here runs in the devcontainer and
# reaches the API server through kind's external port mapping, which works fine.
if [[ "${CODESPACES:-}" == "true" ]]; then
  echo "==> Installing CNI (Flannel)..."
  kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
  echo "==> Waiting for nodes to be Ready..."
  kubectl wait node --for=condition=Ready --all --timeout=180s
fi

# ── Namespaces ────────────────────────────────────────────────────────────────
echo "==> Creating namespaces..."
for ns in payments-dev payments-helm payments-prod monitoring argocd; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

# ── metrics-server (required for HPA) ─────────────────────────────────────────
echo "==> Installing metrics-server..."
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ --force-update 2>/dev/null
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --set args[0]="--kubelet-insecure-tls" \
  --wait

# ── nginx via Kustomize ────────────────────────────────────────────────────────
echo "==> Deploying nginx via Kustomize (dev overlay)..."
kubectl apply -k k8s/overlays/dev

# ── nginx via Helm ────────────────────────────────────────────────────────────
echo "==> Deploying nginx via Helm (payments-helm namespace)..."
helm upgrade --install nginx-app charts/nginx-app \
  --namespace payments-helm \
  --wait

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "Cluster ready. Runtime: $RUNTIME"
echo ""
echo "  kubectl get nodes"
echo "  kubectl get pods,hpa -n payments-dev"
echo "  make watch          # terminal 1"
echo "  make load-test      # terminal 2 — watch HPA scale out"
