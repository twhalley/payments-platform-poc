#!/usr/bin/env bash
# Bootstrap the local kind cluster and install platform components.
# Idempotent — safe to re-run. Deletes and recreates the cluster if it already exists.
# Usage: bash scripts/cluster-setup.sh
set -euo pipefail

export KIND_EXPERIMENTAL_PROVIDER=podman

# ── Cluster ───────────────────────────────────────────────────────────────────
echo "==> Creating kind cluster (rootful Podman)..."
if sudo KIND_EXPERIMENTAL_PROVIDER=podman kind get clusters 2>/dev/null | grep -q "^payments-poc$"; then
  echo "    Cluster already exists, deleting and recreating..."
  sudo KIND_EXPERIMENTAL_PROVIDER=podman kind delete cluster --name payments-poc
fi
sudo KIND_EXPERIMENTAL_PROVIDER=podman kind create cluster --config kind-config.yaml

echo "==> Exporting kubeconfig..."
mkdir -p ~/.kube
sudo KIND_EXPERIMENTAL_PROVIDER=podman kind get kubeconfig --name payments-poc > ~/.kube/config
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
echo "✓ Cluster ready."
echo ""
echo "  kubectl get nodes"
echo "  kubectl get pods,hpa -n payments-dev"
echo "  kubectl port-forward -n payments-dev svc/dev-nginx-app 8080:80"
echo "  k6 run -e TARGET_URL=http://localhost:8080 scripts/load-test.js"
