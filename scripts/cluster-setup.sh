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
