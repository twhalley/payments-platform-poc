#!/usr/bin/env bash
# Bootstrap the cluster and deploy the core platform.
# Idempotent — safe to re-run. Deletes and recreates the cluster if it exists.
#
# Auto-detects the runtime environment:
#   GitHub Codespaces → k3d (k3s in Docker)
#     kind fails in the Codespaces DinD environment: kubectl running inside kind
#     node containers can't reach the API server via the container's bridge IP
#     (hairpin NAT not supported), so CNI and StorageClass installation both fail.
#     k3d bootstraps k3s entirely differently — no in-container kubectl calls.
#   Local             → sudo kind with rootful Podman
#
# Usage: bash scripts/cluster-setup.sh
#        make cluster
set -euo pipefail

# ── Environment detection ──────────────────────────────────────────────────────
if [[ "${CODESPACES:-}" == "true" ]]; then
  RUNTIME="GitHub Codespaces (k3d)"
else
  RUNTIME="local (rootful Podman / kind)"
fi

echo "==> Runtime: $RUNTIME"

# ── Cluster ───────────────────────────────────────────────────────────────────
if [[ "${CODESPACES:-}" == "true" ]]; then
  echo "==> Creating k3d cluster..."
  if k3d cluster list 2>/dev/null | grep -q "payments-poc"; then
    echo "    Cluster already exists — deleting and recreating..."
    k3d cluster delete payments-poc
  fi
  # --disable=traefik: k3s ships Traefik as ingress; we use nginx-unprivileged
  # --agents 1: one server + one agent = 2-node cluster (mirrors kind 2-node setup)
  k3d cluster create payments-poc \
    --agents 1 \
    --k3s-arg "--disable=traefik@server:*" \
    --wait

  echo "==> Exporting kubeconfig..."
  mkdir -p ~/.kube
  k3d kubeconfig get payments-poc > ~/.kube/config
  chmod 600 ~/.kube/config
  export KUBECONFIG=~/.kube/config
else
  echo "==> Creating kind cluster..."
  if sudo KIND_EXPERIMENTAL_PROVIDER=podman kind get clusters 2>/dev/null | grep -q "^payments-poc$"; then
    echo "    Cluster already exists — deleting and recreating..."
    sudo KIND_EXPERIMENTAL_PROVIDER=podman kind delete cluster --name payments-poc
  fi
  sudo KIND_EXPERIMENTAL_PROVIDER=podman kind create cluster --config kind-config.yaml

  echo "==> Exporting kubeconfig..."
  mkdir -p ~/.kube
  sudo KIND_EXPERIMENTAL_PROVIDER=podman kind get kubeconfig --name payments-poc > ~/.kube/config
  chmod 600 ~/.kube/config
  export KUBECONFIG=~/.kube/config
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
