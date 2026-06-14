# payments-platform-poc

Local-first DevSecOps proof-of-concept for a PCI-DSS payments platform: a GitOps-delivered
Kubernetes workload with autoscaling, layered security scanning, software-supply-chain
integrity enforcement, observability, service-mesh mTLS, and infrastructure-as-code
mirroring a GCP/GKE production target.

## What it demonstrates

| Capability | Tool / Pattern |
|---|---|
| Container orchestration | Kubernetes (local kind cluster) |
| App manifests | Kustomize base + dev/prod overlays |
| Platform packages | Helm (ArgoCD, Prometheus, RabbitMQ, Kyverno, Istio) |
| App as Helm chart | `charts/nginx-app/` — authored from scratch |
| GitOps delivery | ArgoCD (pull-based, prune + self-heal) |
| CI/CD pipeline | GitHub Actions (build → scan → sign → GitOps bump) |
| Cloud CI | Google Cloud Build (`cloudbuild.yaml`) |
| AI-powered scanning | Snyk (DeepCode AI, IaC + containers) |
| Multi-scanner | Trivy (CVE + secrets + misconfigs) |
| Static analysis | GitHub CodeQL + Copilot Autofix |
| Supply chain integrity | syft SBOM + cosign keyless sign + SLSA provenance + Kyverno admission gate |
| Autoscaling | HPA — CPU spike demo with k6 load test |
| Observability | Prometheus + Grafana (kube-prometheus-stack) |
| Service mesh / mTLS | Istio PeerAuthentication (STRICT) + AuthorizationPolicy |
| Policy admission | Kyverno (non-root, limits, no-privileged, verify-images) |
| Network segmentation | NetworkPolicy default-deny; VPC + subnets in Terraform |
| Secrets | K8s Secrets + Workload Identity + Cloud KMS (Terraform) |
| Cloud IaC | Terraform: GKE, VPC, Cloud Armor WAF, KMS, Binary Authorization |
| Async payments flow | RabbitMQ (StatefulSet, PDB) + producer/consumer CronJob |
| Local dev loop | Tiltfile — watch-and-sync on manifest change |
| PCI-DSS mapping | `docs/pci-dss-mapping.md` |

## Prerequisites

Run once on a fresh Debian/Ubuntu machine before anything else.

### 1. Install tools

```bash
# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl

# helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# kind (check https://github.com/kubernetes-sigs/kind/releases for latest)
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.30.0/kind-linux-amd64
sudo install -m 0755 kind /usr/local/bin/kind && rm kind

# k6 (load testing — used in the HPA autoscaling demo)
# Binary install — the k6 apt repo GPG key is broken on Debian bookworm
curl -Lo /tmp/k6.tar.gz https://github.com/grafana/k6/releases/download/v2.0.0/k6-v2.0.0-linux-amd64.tar.gz
tar -xzf /tmp/k6.tar.gz -C /tmp
sudo install -m 0755 /tmp/k6-v2.0.0-linux-amd64/k6 /usr/local/bin/k6
# If you previously tried the apt repo, clean it up:
# sudo rm -f /etc/apt/sources.list.d/k6.list /usr/share/keyrings/k6-archive-keyring.gpg
```

### 2. Tell kind to use Podman (add to `~/.bashrc` or `~/.zshrc`)

```bash
export KIND_EXPERIMENTAL_PROVIDER=podman
```

---

## Quickstart

```bash
# 1. Bootstrap the cluster and deploy everything
export KIND_EXPERIMENTAL_PROVIDER=podman
bash scripts/cluster-setup.sh

# 2. Watch HPA autoscaling under load (Phase 2 demo)
kubectl port-forward -n payments-dev svc/dev-nginx-app 8080:80 &
k6 run -e TARGET_URL=http://localhost:8080 scripts/load-test.js

# In a second terminal — watch pods spawn:
kubectl get hpa,pods -n payments-dev -w

# 3. Access Grafana dashboard
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Open http://localhost:3000  admin / poc-admin

# 4. Check ArgoCD sync status
kubectl port-forward -n argocd svc/argocd-server 8443:443
# Open https://localhost:8443

# 5. RabbitMQ management UI
kubectl port-forward -n payments-dev svc/rabbitmq 15672:15672
# Open http://localhost:15672  payments / poc-change-me
```

## Phase-by-phase install

| Phase | What it builds | Key files |
|---|---|---|
| 1 | kind cluster + nginx (Kustomize + Helm) | `kind-config.yaml`, `k8s/`, `charts/nginx-app/` |
| 2 | HPA autoscaling + k6 load test | `k8s/base/hpa.yaml`, `scripts/load-test.js` |
| 3 | ArgoCD GitOps | `argocd/` |
| 4 | GitHub Actions CI (Snyk + Trivy + CodeQL + cosign) | `.github/workflows/ci.yaml` |
| 5 | Prometheus + Grafana | `monitoring/` |
| 6 | Terraform GCP/GKE (plan-validated) | `terraform/` |
| 7 | Istio mTLS + Kyverno + RBAC + NetworkPolicies | `istio/`, `kyverno/`, `k8s/rbac/` |
| 8 | RabbitMQ + payment event flow | `k8s/rabbitmq/` |
| 9 | Cloud Build + Tilt local dev loop | `cloudbuild.yaml`, `Tiltfile` |
| 10 | Supply chain: SBOM + SLSA + admission gate | `kyverno/policies/verify-images.yaml`, `.github/workflows/supply-chain.yaml` |

## JD mapping

| JD requirement | Where in this repo |
|---|---|
| Production Kubernetes (GKE) | `kind-config.yaml`, `terraform/gke.tf` |
| Terraform for GCP | `terraform/` (plan-validated against GKE) |
| CI/CD — Google Cloud Build + GitHub Actions | `cloudbuild.yaml`, `.github/workflows/` |
| DNS, TLS/mTLS, load balancing | Istio mTLS (`istio/`), ingress port mappings (`kind-config.yaml`) |
| Docker / container lifecycle | `Dockerfile`, container fields in `k8s/base/deployment.yaml` |
| GitOps — ArgoCD + Kustomize | `argocd/application.yaml`, `k8s/overlays/` |
| Istio / service mesh | `istio/peer-authentication.yaml`, `istio/authorization-policy.yaml` |
| PCI-DSS at infrastructure level | `docs/pci-dss-mapping.md`, Kyverno policies, NetworkPolicies, KMS |
| GCP: KMS, Cloud Armor, Binary Authorization | `terraform/kms.tf`, `terraform/vpc.tf` (Cloud Armor), `terraform/gke.tf` (Binary Auth) |
| Local Kubernetes dev tooling (Tilt) | `Tiltfile` |
| Prometheus + Grafana | `monitoring/values-kube-prometheus-stack.yaml` |
| Snyk (AI scanning) | `.github/workflows/ci.yaml` — Snyk IaC step |
| Trivy (multi-scanner) | `.github/workflows/ci.yaml` — Trivy image + fs steps |
| Supply chain / Binary Authorization | `kyverno/policies/verify-images.yaml`, `.github/workflows/supply-chain.yaml` |
| RabbitMQ async payment flow | `k8s/rabbitmq/` |
| Helm | `charts/nginx-app/` (authored), platform charts (consumed) |

## Note on scope

Runs on a local **kind** cluster by design — the role explicitly values "keeping local
development environments working so engineers can run the full stack on their machines"
and names Tilt. Cloud IaC (`terraform/`) is real and `terraform plan`-validated against
GKE; it is demonstrated without live GCP spend.
