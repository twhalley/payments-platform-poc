#!/usr/bin/env bash
# Bootstrap the local kind cluster and install platform components.
# Run once after cloning: bash scripts/cluster-setup.sh
set -euo pipefail

export KIND_EXPERIMENTAL_PROVIDER=podman

echo "==> Creating kind cluster (rootful Podman — no session restart required)..."
sudo KIND_EXPERIMENTAL_PROVIDER=podman kind create cluster --config kind-config.yaml

echo "==> Exporting kubeconfig for current user..."
mkdir -p ~/.kube
sudo kind get kubeconfig --name payments-poc > ~/.kube/config
chmod 600 ~/.kube/config

echo "==> Creating namespaces..."
kubectl create namespace payments-dev  --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace payments-helm --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace payments-prod --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace monitoring    --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace argocd        --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing metrics-server (required for HPA)..."
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ --force-update
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --set args[0]="--kubelet-insecure-tls" \
  --wait

echo "==> Deploying nginx via Kustomize (dev overlay)..."
kubectl apply -k k8s/overlays/dev

echo "==> Deploying nginx via Helm (payments-helm namespace)..."
helm upgrade --install nginx-app charts/nginx-app \
  --namespace payments-helm \
  --wait

echo ""
echo "Cluster ready. Try:"
echo "  kubectl get pods,hpa -n payments-dev"
echo "  kubectl port-forward -n payments-dev svc/dev-nginx-app 8080:80"
echo "  k6 run -e TARGET_URL=http://localhost:8080 scripts/load-test.js"
