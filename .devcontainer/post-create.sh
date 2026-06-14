#!/usr/bin/env bash
# Runs once after the Codespace / DevContainer is created.
# Installs tools not covered by devcontainer features.
set -euo pipefail

echo "==> Installing kind..."
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.30.0/kind-linux-amd64
sudo install -m 0755 kind /usr/local/bin/kind && rm kind

echo "==> Installing k6 v2.0.0..."
curl -Lo /tmp/k6.tar.gz https://github.com/grafana/k6/releases/download/v2.0.0/k6-v2.0.0-linux-amd64.tar.gz
tar -xzf /tmp/k6.tar.gz -C /tmp
sudo install -m 0755 /tmp/k6-v2.0.0-linux-amd64/k6 /usr/local/bin/k6

echo "==> Installing cosign..."
COSIGN_VERSION=$(curl -s https://api.github.com/repos/sigstore/cosign/releases/latest | grep tag_name | cut -d'"' -f4)
curl -Lo /tmp/cosign "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-amd64"
sudo install -m 0755 /tmp/cosign /usr/local/bin/cosign

echo "==> Installing syft..."
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sudo sh -s -- -b /usr/local/bin

echo ""
echo "All tools installed. Run: make cluster"
