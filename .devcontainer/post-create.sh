#!/usr/bin/env bash
# Runs once after the Codespace / DevContainer is created.
# Installs all tools needed for the full demo and security scan targets.
# kubectl and helm are installed by the devcontainer feature — this script
# handles everything else.
set -euo pipefail

echo "==> Installing system packages..."
sudo apt-get update -qq
sudo apt-get install -y -qq jq python3-pip unzip

echo "==> Installing kind v0.32.0..."
curl -Lo /tmp/kind https://kind.sigs.k8s.io/dl/v0.32.0/kind-linux-amd64
sudo install -m 0755 /tmp/kind /usr/local/bin/kind && rm /tmp/kind

echo "==> Installing k6 v2.0.0..."
curl -Lo /tmp/k6.tar.gz https://github.com/grafana/k6/releases/download/v2.0.0/k6-v2.0.0-linux-amd64.tar.gz
tar -xzf /tmp/k6.tar.gz -C /tmp
sudo install -m 0755 /tmp/k6-v2.0.0-linux-amd64/k6 /usr/local/bin/k6
rm -rf /tmp/k6.tar.gz /tmp/k6-v2.0.0-linux-amd64

echo "==> Installing cosign v2.2.4..."
curl -Lo /tmp/cosign https://github.com/sigstore/cosign/releases/download/v2.2.4/cosign-linux-amd64
sudo install -m 0755 /tmp/cosign /usr/local/bin/cosign && rm /tmp/cosign

echo "==> Installing syft (SBOM generator)..."
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sudo sh -s -- -b /usr/local/bin

echo "==> Installing grype (SBOM vulnerability scanner)..."
curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sudo sh -s -- -b /usr/local/bin

echo "==> Installing Trivy v0.51.0..."
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
  | sudo sh -s -- -b /usr/local/bin v0.51.0

echo "==> Installing Kyverno CLI v1.12.0..."
curl -Lo /tmp/kyverno-cli.tar.gz \
  https://github.com/kyverno/kyverno/releases/download/v1.12.0/kyverno-cli_v1.12.0_linux_x86_64.tar.gz
tar -xzf /tmp/kyverno-cli.tar.gz -C /tmp kyverno
sudo install -m 0755 /tmp/kyverno /usr/local/bin/kyverno
rm -f /tmp/kyverno-cli.tar.gz /tmp/kyverno

echo "==> Installing pre-commit + hooks..."
pip3 install --quiet pre-commit
# Set up hooks so they run automatically on every git commit
pre-commit install || true   # non-fatal if not in a git repo yet

echo "==> Configuring KUBECONFIG..."
mkdir -p ~/.kube
# Persist KUBECONFIG across shell sessions
grep -q 'KUBECONFIG' ~/.bashrc 2>/dev/null || echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
grep -q 'KUBECONFIG' ~/.zshrc  2>/dev/null || echo 'export KUBECONFIG=~/.kube/config' >> ~/.zshrc 2>/dev/null || true

echo ""
echo "All tools installed:"
echo "  kind    $(kind --version)"
echo "  kubectl $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
echo "  helm    $(helm version --short)"
echo "  k6      $(k6 version)"
echo "  cosign  $(cosign version 2>/dev/null | head -1)"
echo "  trivy   $(trivy --version | head -1)"
echo "  kyverno $(kyverno version 2>/dev/null | head -1)"
echo ""
echo "Next step: make cluster"
echo ""
echo "Quick security demos (no cluster needed):"
echo "  make security-scan"
echo "  make kyverno-test"
