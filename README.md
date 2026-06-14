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

### 2. Rootful Podman for kind — a note on the tradeoff

The setup script creates the kind cluster using `sudo kind` (rootful Podman). This is a
deliberate PoC simplification: rootless Podman requires systemd cgroup delegation
(`Delegate=yes`) to take effect on a fresh login session, which adds friction to a demo.

**Why rootful is fine here:** this is a local, single-user demo machine with no sensitive
workloads. The security boundary that matters for this PoC is inside the cluster — the
Kyverno policies, NetworkPolicies, securityContext hardening, and Istio mTLS — not the
container runtime on the host.

**What you'd do in production:** on GKE this is a non-issue — the managed control plane
handles cgroup delegation transparently and nodes run containerd, not Podman. On a
self-managed or on-prem cluster you'd configure rootless with `Delegate=yes` and a full
session restart, which is the correct hardening posture (a compromised rootful container
has root on the host; a rootless one does not).

### 3. Tell kind to use Podman (add to `~/.bashrc` or `~/.zshrc`)

```bash
export KIND_EXPERIMENTAL_PROVIDER=podman
```

---

## Demo walkthrough

Run `bash scripts/cluster-setup.sh` first, then step through each section below in order.

---

### 1. Cluster and nodes

```bash
kubectl get nodes
kubectl get pods -n payments-dev
kubectl get pods -n payments-helm
```

Two nodes (control-plane + worker). nginx is running in two namespaces — deployed two
different ways — which leads into the next step.

> *"I'm running on a local kind cluster, two nodes, which directly mirrors GKE. The role
> values local dev environments — this is the full stack on one machine."*

---

### 2. Kustomize vs Helm — two delivery paths

**Show Kustomize:**
```bash
kubectl kustomize k8s/overlays/dev   # render the dev overlay without applying
kubectl get deployment -n payments-dev dev-nginx-app -o yaml
```

Open `k8s/base/deployment.yaml` and walk through the hardening fields:
- `runAsNonRoot: true` + `runAsUser: 101` — uses `nginx-unprivileged` image, not the root-default `nginx`
- `readOnlyRootFilesystem: true` — three `emptyDir` mounts for the paths nginx needs to write
- `allowPrivilegeEscalation: false` + `capabilities: drop: ALL`
- `resources.requests.cpu: 25m` — intentionally low so the HPA triggers fast in the demo
- All three probe types: `readinessProbe`, `livenessProbe`, `startupProbe`

**Show Helm:**
```bash
helm list -n payments-helm
helm get values nginx-app -n payments-helm
helm history nginx-app -n payments-helm
```

Open `charts/nginx-app/` — authored from scratch, not `helm create`.

> *"Kustomize for our own services: patch-based, no templating, diff-friendly, and ArgoCD
> renders it natively. Helm for platform components with versioned releases and `helm
> rollback`. Same workload, both paths running side by side."*

---

### 3. HPA autoscaling — watch pods spawn under load

Open **two terminals**.

**Terminal 1** — watch in real time:
```bash
kubectl get hpa,pods -n payments-dev -w
```

**Terminal 2** — port-forward then fire the load test:
```bash
kubectl port-forward -n payments-dev svc/dev-nginx-app 8080:80 &
k6 run -e TARGET_URL=http://localhost:8080 scripts/load-test.js
```

The HPA (`k8s/base/hpa.yaml`) triggers at 50% of the `25m` CPU request. Watch replicas
climb from 3 toward 6. After load stops, pods scale back down after the 60s stabilisation
window.

> *"CPU request is deliberately low so the HPA fires quickly under demo load. The
> scale-up stabilisation window is 15 seconds; scale-down is 60 to prevent flapping.
> In production you'd tune both to your actual baseline."*

---

### 4. ArgoCD — GitOps pull-based delivery

```bash
helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --values argocd/values-argocd.yaml \
  --wait

kubectl apply -f argocd/application.yaml

kubectl port-forward -n argocd svc/argocd-server 8443:443
```

Open `https://localhost:8443`. Show the app in sync, then open `argocd/application.yaml`:
- `automated.prune: true` — removes resources deleted from git
- `automated.selfHeal: true` — reverts manual `kubectl edit` changes automatically

> *"Pull-based GitOps — ArgoCD polls the repo, not the other way around. `selfHeal` means
> if someone makes a manual change at 2am, ArgoCD reverts it within 3 minutes. Every
> change is a signed Git commit — that's your audit trail for PCI-DSS Requirement 12."*

---

### 5. GitHub Actions CI pipeline

Open `.github/workflows/ci.yaml` on GitHub and walk through the five jobs:

1. **lint** — Kustomize dry-run + `helm lint` before anything builds
2. **snyk** — AI-powered IaC scan (Terraform + K8s manifests), results in GitHub Security tab
3. **codeql** — GitHub's AI static analysis; raises inline fix suggestions on PR diffs
4. **build-scan** — builds the image, then Trivy scans for CVEs/secrets/misconfigs; exits 1 on CRITICAL/HIGH
5. **sign** — cosign keyless signing via GitHub OIDC + syft SBOM attached as attestation
6. **deploy** — bumps the image tag in the Kustomize overlay; ArgoCD picks it up automatically

> *"Two AI scanners in parallel — Snyk's DeepCode engine for IaC and containers, CodeQL
> with Copilot Autofix for static analysis. Running both means I'm not trusting a single
> vendor. The developer sees the issue before it merges — that's shift-left."*

---

### 6. Prometheus + Grafana — observability

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm upgrade --install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --values monitoring/values-kube-prometheus-stack.yaml \
  --wait

kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

Open `http://localhost:3000` — admin / poc-admin. Navigate to the Kubernetes HPA
dashboard (ID 10257) to see the scale event from step 3.

> *"Observability is how you know about a problem before your customers do. Any pod
> annotated `prometheus.io/scrape: true` is picked up automatically — no per-service
> config needed."*

---

### 7. RabbitMQ — async payment event flow

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami --force-update
helm upgrade --install rabbitmq bitnami/rabbitmq \
  --namespace payments-dev \
  --values k8s/rabbitmq/values-rabbitmq.yaml \
  --wait

kubectl create secret generic rabbitmq-url \
  --namespace payments-dev \
  --from-literal=url="amqp://payments:poc-change-me@rabbitmq.payments-dev.svc:5672/payments" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f k8s/rabbitmq/pdb.yaml
kubectl apply -f k8s/rabbitmq/consumer-deployment.yaml
kubectl apply -f k8s/rabbitmq/producer-job.yaml

# Watch payment events flow through the queue
kubectl logs -n payments-dev -l app.kubernetes.io/name=payment-consumer -f --max-log-requests=3
```

Show the management UI:
```bash
kubectl port-forward -n payments-dev svc/rabbitmq 15672:15672
# http://localhost:15672  payments / poc-change-me
```

Open `k8s/rabbitmq/pdb.yaml` — `minAvailable: 2` ensures quorum is maintained during
node drains. Open `k8s/rabbitmq/producer-job.yaml` — `delivery_mode=2` makes messages
persistent across broker restarts.

> *"Payment orchestration across dozens of processes is inherently async. A broker
> decouples authorisation, tokenisation, fraud check, and settlement — a slow settlement
> service doesn't block the others. `delivery_mode=2` means a message survives a broker
> restart. If the consumer crashes mid-process, the unACKed message re-queues. That's
> how you avoid losing a payment."*

---

### 8. Istio mTLS + Kyverno policy admission

**Kyverno:**
```bash
helm repo add kyverno https://kyverno.github.io/kyverno --force-update
helm upgrade --install kyverno kyverno/kyverno \
  --namespace kyverno --create-namespace \
  --wait

kubectl apply -f kyverno/policies/require-non-root.yaml
kubectl apply -f kyverno/policies/require-resource-limits.yaml
kubectl apply -f kyverno/policies/block-privileged.yaml
```

Try to deploy a non-compliant pod — watch Kyverno block it:
```bash
kubectl run bad-pod --image=nginx --namespace payments-dev
# Expected: Error from server: admission webhook denied the request
```

Open `kyverno/policies/require-non-root.yaml` and show the `validationFailureAction: Enforce` field.

**Istio mTLS:**
```bash
helm repo add istio https://istio-release.storage.googleapis.com/charts --force-update
helm upgrade --install istio-base istio/base --namespace istio-system --create-namespace --wait
helm upgrade --install istiod istio/istiod --namespace istio-system --wait

kubectl apply -f istio/peer-authentication.yaml
kubectl apply -f istio/authorization-policy.yaml
```

Open `istio/peer-authentication.yaml` — `mode: STRICT` means all pods in `payments-dev`
must use mutual TLS. Plaintext is rejected.

> *"Kyverno is the policy admission controller — it intercepts the API server request
> before a pod is scheduled. Unsigned, root-running, or resource-unlimited containers
> are rejected at the gate. Istio mTLS covers Requirement 4 of PCI-DSS: all
> service-to-service traffic is encrypted in transit with mutual certificate auth."*

---

### 9. Terraform — GCP/GKE infrastructure as code

```bash
cd terraform
terraform init
terraform plan -var-file=../example.tfvars
```

Walk through the plan output and open the files:
- `gke.tf` — private nodes, Workload Identity, Binary Authorization enforced, Shielded Nodes
- `vpc.tf` — private subnet with secondary ranges for pods/services; Cloud Armor WAF rule blocking XSS + SQLi
- `kms.tf` — envelope encryption for etcd and app secrets, 90-day automatic key rotation, `prevent_destroy` lifecycle guard

> *"This is real Terraform — it would apply against GCP as-is. I'm demonstrating with
> `terraform plan` rather than spending on live infrastructure. Binary Authorization here
> is the GCP-native equivalent of the Kyverno verifyImages policy — only attested images
> run. KMS covers PCI-DSS Requirement 3: protect stored account data."*

```bash
cd ..
```

---

### 10. Supply chain integrity — SBOM + signing + admission gate

This is the end-to-end supply chain story. Open `.github/workflows/ci.yaml` and
`.github/workflows/supply-chain.yaml` together.

**The chain:**
1. **syft** generates an SPDX SBOM at build time — answers "do we ship Log4j?" instantly
2. **cosign keyless** signs the image using the GitHub Actions OIDC token — no long-lived keys
3. **SLSA provenance** attestation is attached — proves which pipeline workflow built the image
4. **Kyverno verifyImages** (`kyverno/policies/verify-images.yaml`) verifies the signature at
   admission time — unsigned images are rejected before they're scheduled

Show what rejection looks like by trying to deploy an unsigned third-party image into the
`payments-dev` namespace once the verifyImages policy is applied:
```bash
kubectl apply -f kyverno/policies/verify-images.yaml
kubectl run unsigned --image=alpine --namespace payments-dev
# Expected: admission webhook denied — image not signed by your pipeline
```

> *"Scanning in CI tells you whether an image has known vulnerabilities. Supply chain
> integrity answers a completely different question: is the thing running in my cluster
> actually what I built, or did someone tamper with it between build and deploy?
> Keyless signing means no keys to rotate or leak — the signature proves it was built
> by this specific GitHub Actions workflow. The Kyverno gate means that control cannot
> be bypassed by pushing directly to the registry. This maps directly to GCP Binary
> Authorization, which is the 'set you apart' bullet in the JD."*

---

### 11. PCI-DSS audit mapping

```bash
cat docs/pci-dss-mapping.md
```

Walk down the table — every requirement points to a specific file.

> *"Audit readiness isn't just having the controls — it's being able to point an auditor
> at evidence immediately. Signed commits in ArgoCD are the change log, Kyverno policies
> are the enforcement evidence, KMS rotation is automatic and logged in Cloud Audit Logs."*

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
