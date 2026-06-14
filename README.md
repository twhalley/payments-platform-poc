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
| Platform packages | Helm (ArgoCD, Prometheus, RabbitMQ, Kyverno, Istio, Falco) |
| App as Helm chart | `charts/nginx-app/` — authored from scratch |
| GitOps delivery | ArgoCD (pull-based, prune + self-heal) |
| CI/CD pipeline | GitHub Actions (build → scan → sign → GitOps bump) |
| Cloud CI | Google Cloud Build (`cloudbuild.yaml`) |
| AI-powered scanning | Snyk (DeepCode AI, IaC + containers) |
| Multi-scanner | Trivy (CVE + secrets + misconfigs) |
| Static analysis | GitHub CodeQL + Copilot Autofix |
| Supply chain integrity | syft SBOM + cosign keyless sign + SLSA provenance + Kyverno admission gate |
| Autoscaling | HPA — CPU spike demo with k6 load test |
| Observability | Prometheus + Grafana + Loki (PLG stack — metrics + logs in one pane) |
| Alerting | AlertManager rules: HPA at max, pod crash loop, RabbitMQ queue depth |
| DAST | OWASP ZAP baseline scan on every push — HTML report as CI artifact |
| Service mesh / mTLS | Istio PeerAuthentication (STRICT) + AuthorizationPolicy |
| Policy admission | Kyverno + Pod Security Standards (two independent gates) |
| Runtime security | Falco — syscall-level threat detection |
| Network segmentation | NetworkPolicy default-deny + explicit allow; VPC in Terraform |
| Secrets | K8s Secrets + Workload Identity + Cloud KMS (Terraform) |
| Cloud IaC | Terraform: GKE, VPC, Cloud Armor WAF, KMS, Binary Authorization |
| Async payments flow | RabbitMQ (StatefulSet, PDB) + producer/consumer CronJob |
| Local dev loop | Tiltfile — watch-and-sync on manifest change |
| PCI-DSS mapping | `docs/pci-dss-mapping.md` |

---

## Run anywhere — GitHub Codespaces

The fastest way to run this on any machine is GitHub Codespaces. No local installs needed.

1. Open the repo on GitHub
2. Click **Code → Codespaces → Create codespace on master**
3. Wait ~2 minutes for the DevContainer to build (installs kind, k6, cosign, syft automatically)
4. In the Codespaces terminal: `make cluster`

Port forwards (8080, 3000, 8443, 15672) are auto-configured in `.devcontainer/devcontainer.json`.

> *"I set up a DevContainer so any engineer on the team can clone this and have the full
> stack running in a Codespace in under 5 minutes — no 'works on my machine' problems."*

---

## Local prerequisites (Debian/Ubuntu — skip if using Codespaces)

### 1. Install tools

```bash
# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl

# helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# kind
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.30.0/kind-linux-amd64
sudo install -m 0755 kind /usr/local/bin/kind && rm kind

# k6 — binary install (apt repo GPG key is broken on Debian bookworm)
curl -Lo /tmp/k6.tar.gz https://github.com/grafana/k6/releases/download/v2.0.0/k6-v2.0.0-linux-amd64.tar.gz
tar -xzf /tmp/k6.tar.gz -C /tmp
sudo install -m 0755 /tmp/k6-v2.0.0-linux-amd64/k6 /usr/local/bin/k6
# If you previously tried the apt repo, clean it up:
# sudo rm -f /etc/apt/sources.list.d/k6.list /usr/share/keyrings/k6-archive-keyring.gpg
```

### 2. Rootful Podman for kind — tradeoff

The setup script uses `sudo kind` (rootful Podman). Rootless Podman requires `Delegate=yes`
in systemd and a full session restart, which adds friction to a demo.

**Why rootful is fine here:** the security boundary that matters is inside the cluster —
Kyverno, NetworkPolicies, Istio mTLS — not the container runtime on the host.

**In production:** GKE handles cgroup delegation transparently (managed control plane,
containerd not Podman). On self-managed clusters you'd configure rootless with `Delegate=yes`.
A compromised rootful container has root on the host; a rootless one does not.

### 3. Set Podman provider (add to `~/.bashrc` or `~/.zshrc`)

```bash
export KIND_EXPERIMENTAL_PROVIDER=podman
```

---

## GitHub Actions — enabling the CI pipeline

The workflows in `.github/workflows/` are already written. To make them run:

1. **Add `SNYK_TOKEN` secret** — GitHub repo → Settings → Secrets and variables → Actions → New repository secret
   - Get a free token at [snyk.io](https://snyk.io) → Account Settings → API Token

2. **Enable GHCR** — the `GITHUB_TOKEN` already has `packages: write` in the workflow, so image pushes work automatically on push to `master`

3. **Enable CodeQL** — GitHub repo → Security → Code scanning → Set up → Advanced (uses the existing workflow)

4. **Trigger the pipeline** — push any commit to `master` or open a PR. Watch the pipeline at:
   GitHub repo → Actions tab

**What runs on every PR:**
- Kustomize + Helm lint
- Snyk IaC scan → results in Security tab
- CodeQL static analysis → inline PR annotations
- Trivy image scan → fails the build on CRITICAL/HIGH CVEs

**What runs on merge to master:**
- All of the above, plus:
- cosign keyless image signing (no keys to manage — uses GitHub OIDC)
- syft SBOM generation + attached as image attestation
- SLSA provenance attestation
- Kustomize overlay image-tag bump → ArgoCD picks it up automatically

> *"The pipeline is pinned — `snyk/actions/iac@1.1.2`, `trivy-action@0.24.0` — not `@master`.
> Mutable action refs are a supply chain attack vector: the action could change between
> runs. Pinning to a version means what ran yesterday runs the same way today."*

---

## Security audit — what was found and fixed

A full audit was run against this project. Summary of findings and resolutions:

### Fixed (Critical)

| Finding | Fix |
|---|---|
| `snyk/actions/iac@master` — mutable ref | Pinned to `@1.1.2` |
| `trivy-action@master` — mutable ref | Pinned to `@0.24.0` |
| `continue-on-error: true` on security scans | Removed — CRITICAL/HIGH now fails the build |
| `python:3.12-alpine` mutable image tag | Pinned to `3.12.9-alpine3.21` |
| `aquasec/trivy:latest` in Cloud Build | Pinned to `0.51.0` |
| Consumer `readOnlyRootFilesystem: false` | Fixed to `true` + `emptyDir` for `/tmp` |
| Grafana password committed to values file | Removed — passed via `--set` at install time only |

### Fixed (High)

| Finding | Fix |
|---|---|
| NetworkPolicy ingress had no `from:` clause | Restricted to `ingress-nginx` + `istio-system` namespaces |
| No `imagePullPolicy` on base deployment | Added `IfNotPresent` explicitly |
| No PodDisruptionBudget for nginx | Added `k8s/base/pdb.yaml` (`minAvailable: 1`) |
| No NetworkPolicy for RabbitMQ egress | Added `k8s/rabbitmq/networkpolicy.yaml` (port 5672 only) |
| Prometheus retention 7 days | Increased to 30 days (PCI-DSS audit trail) |

### Accepted trade-offs (Medium/Low — documented, not production blockers)

| Finding | Status |
|---|---|
| Kyverno policies scoped to specific namespaces only | Acceptable for PoC; production would scope cluster-wide |
| Terraform API endpoint `enable_private_endpoint: false` | Documented — needed for demo access; production would use bastion |
| KMS rotation at 90 days | Within PCI-DSS tolerance; 30 days is stricter but optional |
| RabbitMQ default permissions `.*` | Acceptable for PoC; production would scope per queue family |
| ArgoCD TLS disabled (`--insecure`) | Local only; production terminates TLS at ingress/mesh layer |

---

## Demo walkthrough

Use `make` targets — each maps to one demo step.

```bash
make cluster    # start here — boots the cluster and deploys nginx both ways
```

---

### 1. Cluster and nodes

```bash
kubectl get nodes
kubectl get pods -n payments-dev
kubectl get pods -n payments-helm
```

Two nodes (control-plane + worker). nginx is running in two namespaces, deployed two ways.

> *"Local kind cluster, two nodes — directly mirrors a GKE setup. The role values local dev
> environments; this is the full stack on one machine with no cloud spend."*

---

### 2. Kustomize vs Helm — two delivery paths

```bash
kubectl kustomize k8s/overlays/dev   # render the overlay without applying
kubectl get deployment -n payments-dev dev-nginx-app -o yaml
```

Open `k8s/base/deployment.yaml` and walk through:
- `runAsNonRoot: true` + `runAsUser: 101` — `nginx-unprivileged` image, not root-default `nginx`
- `readOnlyRootFilesystem: true` — three `emptyDir` mounts for paths nginx needs to write
- `allowPrivilegeEscalation: false` + `capabilities: drop: ALL`
- `seccompProfile: RuntimeDefault` — kernel syscall filtering
- `resources.requests.cpu: 25m` — intentionally low so HPA fires fast in the demo
- All three probes: `readinessProbe`, `livenessProbe`, `startupProbe`
- `minAvailable: 1` PodDisruptionBudget — service survives a node drain

```bash
helm list -n payments-helm
helm history nginx-app -n payments-helm    # show versioned release history
```

Open `charts/nginx-app/` — `Chart.yaml`, `values.yaml`, `templates/_helpers.tpl` — authored
from scratch.

> *"Kustomize for our own services: patch-based, no templating, diff-friendly, ArgoCD renders
> it natively. Helm for platform components with versioned releases and `helm rollback`. I can
> show both delivery paths running side-by-side, and I authored this chart rather than just
> consuming one."*

---

### 3. HPA autoscaling — watch pods spawn under load

This is the most visual demo moment. Open **two terminals**.

**Terminal 1 — watch the HPA and pods in real time:**
```bash
make watch
# or: kubectl get hpa,pods -n payments-dev -w
```

What you will see:
```
NAME                             REFERENCE              TARGETS   MINPODS   MAXPODS   REPLICAS
horizontalpodautoscaler/dev-nginx-app   Deployment/dev-nginx-app   5%/50%    2         6         3

NAME                            READY   STATUS    RESTARTS
pod/dev-nginx-app-xxx-aaa       1/1     Running   0
pod/dev-nginx-app-xxx-bbb       1/1     Running   0
pod/dev-nginx-app-xxx-ccc       1/1     Running   0
```

**Terminal 2 — fire the load test:**
```bash
make load-test
# or: kubectl port-forward -n payments-dev svc/dev-nginx-app 8080:80 &
#     k6 run -e TARGET_URL=http://localhost:8080 scripts/load-test.js
```

k6 ramps: **20 VUs → 100 VUs → 200 VUs → 0**. Watch Terminal 1 as this happens:

1. CPU% column climbs past 50% (the HPA threshold)
2. `REPLICAS` jumps: `3 → 5 → 6` within ~15 seconds (the scale-up stabilisation window)
3. New pods appear as `Pending → ContainerCreating → Running`
4. After load stops, replicas drain back to 3 after the 60s scale-down window

k6 output shows:
```
✓ status 200
✓ body contains payments
http_req_duration p(95)=<500ms
```

> *"CPU request is deliberately low at 25 millicores so the HPA fires quickly under demo load.
> Scale-up stabilisation is 15 seconds to respond fast; scale-down is 60 seconds to prevent
> flapping. The PodDisruptionBudget means at least one pod stays up during any node drain —
> you can't accidentally take the service fully offline."*

---

### 4. ArgoCD — GitOps pull-based delivery

```bash
make argocd
kubectl port-forward -n argocd svc/argocd-server 8443:443
```

Open `https://localhost:8443`. Show the app in sync, then open `argocd/application.yaml`:
- `automated.prune: true` — removes resources deleted from git
- `automated.selfHeal: true` — reverts manual `kubectl edit` changes automatically

**Live demo:** make a small change in the dev overlay (e.g. bump replicas), commit and push,
and watch ArgoCD detect drift and reconcile within 3 minutes without any manual `kubectl apply`.

> *"Pull-based GitOps — ArgoCD polls the repo, not the other way around. `selfHeal` means if
> someone makes a manual kubectl change at 2am, ArgoCD reverts it on the next sync. Every
> change to this cluster is a signed Git commit — that's the audit trail for PCI-DSS Req 12."*

---

### 5. GitHub Actions CI pipeline

Open `.github/workflows/ci.yaml` on GitHub and walk through the jobs:

1. **lint** — Kustomize dry-run + `helm lint` before anything builds
2. **snyk** — AI-powered IaC scan; results appear in the GitHub Security tab
3. **codeql** — GitHub AI static analysis with Copilot Autofix suggestions on PR diffs
4. **build-scan** — builds the image, Trivy scans for CVEs/secrets/misconfigs, exits 1 on CRITICAL/HIGH
5. **sign** — cosign keyless signing via GitHub OIDC + syft SBOM attached as attestation
6. **deploy** — bumps the image tag in the Kustomize overlay; ArgoCD picks it up automatically

Point at the pinned action versions:
```yaml
uses: snyk/actions/iac@1.1.2         # not @master
uses: aquasecurity/trivy-action@0.24.0  # not @master
```

> *"Two AI scanners in parallel — Snyk's DeepCode engine and CodeQL with Copilot Autofix.
> Running both means I'm not trusting a single vendor. Actions are pinned to specific versions,
> not @master — a mutable ref is a supply chain attack vector. The developer sees the issue
> in the PR before it merges — that's what shift-left means in practice."*

---

### 6. Prometheus + Grafana — observability

```bash
make prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

Open `http://localhost:3000` — admin / poc-admin.

Navigate to **Dashboards → Kubernetes HPA** (imported automatically, ID 10257). If you ran
the load test in step 3, you'll see the replica count spike and the CPU metric that triggered it.

> *"Observability is how you know about a problem before your customers do. Any pod annotated
> `prometheus.io/scrape: true` is picked up automatically. The Grafana dashboard lets on-call
> see the HPA scale event, CPU utilisation, and request latency in one view."*

---

### 7. RabbitMQ — async payment event flow

```bash
make rabbitmq
```

Watch events flow:
```bash
kubectl logs -n payments-dev -l app.kubernetes.io/name=payment-consumer -f --max-log-requests=3
# [consumer] Processing a3f2c1d0-... £10.00
# [consumer] ACKed a3f2c1d0-...
```

Management UI:
```bash
kubectl port-forward -n payments-dev svc/rabbitmq 15672:15672
# http://localhost:15672  payments / poc-change-me
```

In the UI, show the `payment.authorised` queue filling and draining. Navigate to
**Queues → payment.authorised** to see message rates, consumers, and the dead-letter
queue configured for failed deliveries.

Open `k8s/rabbitmq/values-rabbitmq.yaml`:
- `replicaCount: 3` — quorum; losing 1 node still has a majority
- `k8s/rabbitmq/pdb.yaml` — `minAvailable: 2` ensures quorum survives a node drain

Open `k8s/rabbitmq/producer-job.yaml`:
- `delivery_mode=2` — messages survive a broker restart
- Consumer ACKs only after processing — unACKed messages re-queue on consumer crash

> *"Payment orchestration is inherently async — authorisation, tokenisation, fraud check,
> settlement, CRM update. A broker decouples them: a slow settlement step doesn't block
> the others, a traffic spike queues rather than knocking services over, and a consumer
> crash doesn't lose the payment — the unACKed message re-queues. That's guaranteed
> delivery, which is non-negotiable for payments."*

---

### 8. Kyverno + Pod Security Standards — two admission gates

```bash
make kyverno
```

**Gate 1 — Kubernetes Pod Security Standards (API server level):**
```bash
kubectl label namespace payments-dev \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted

# Check for any violations before enforcing:
kubectl get events -n payments-dev --field-selector reason=FailedCreate

# Once clean, enforce:
kubectl label namespace payments-dev pod-security.kubernetes.io/enforce=restricted --overwrite
```

**Gate 2 — Kyverno (admission webhook level):**
```bash
# Try to deploy a non-compliant pod — show it being blocked at the webhook:
kubectl run bad-pod --image=nginx --namespace payments-dev
# Error from server: admission webhook denied the request:
# Containers must set runAsNonRoot: true
```

Two independent gates: PSS enforces at the API server before the request reaches Kyverno.
If one is misconfigured, the other still fires.

Open `kyverno/policies/require-non-root.yaml` — `validationFailureAction: Enforce`.
Open `kyverno/policies/pod-security-standards.yaml` — explains the layered approach.

> *"Two independent admission gates. PSS is built into the API server — no webhook, no
> dependency on a running pod. Kyverno runs as an admission webhook and gives you richer
> policy logic and audit reporting. Together they're defense-in-depth at the scheduling layer."*

---

### 9. Istio mTLS

```bash
make istio
```

Open `istio/peer-authentication.yaml` — `mode: STRICT` — all pods in `payments-dev` must
use mutual TLS. Plaintext is rejected at the sidecar proxy.

Open `istio/authorization-policy.yaml` — deny-all, then explicit allow only for:
- Ingress gateway → nginx on port 8080
- Prometheus → nginx metrics scrape

> *"Istio mTLS covers PCI-DSS Requirement 4: all service-to-service traffic encrypted in
> transit with mutual certificate authentication. The authorization policy implements
> Requirement 7: default-deny, explicit allow only for known service identity pairs.
> If a pod is compromised and tries to talk to another service, its Istio certificate
> won't be in the allow list — the request is dropped at the sidecar."*

---

### 10. Falco — runtime threat detection

```bash
make falco
```

Watch for runtime alerts:
```bash
kubectl logs -n falco -l app.kubernetes.io/name=falco -f
```

Trigger a detection to show it working:
```bash
# Shell into a running pod — Falco detects unexpected terminal shells in containers
kubectl exec -n payments-dev -it $(kubectl get pod -n payments-dev -l app.kubernetes.io/name=nginx-app -o name | head -1) -- /bin/sh
```

Falco will log:
```
Notice A shell was spawned in a container with an attached terminal
  (user=root container=nginx-app image=nginx-unprivileged)
```

> *"Kyverno and PSS prevent bad pods from being scheduled. Falco watches what's happening
> inside running containers at the syscall level. If an attacker gets into a running pod
> and spawns a shell, reads /etc/shadow, or starts a network scan — Falco detects it in
> real time. That's the difference between prevention and detection. You need both."*

---

### 11. Terraform — GCP/GKE infrastructure as code

```bash
make terraform-plan
```

Walk through the plan output and open the files:
- `terraform/gke.tf` — private nodes, Workload Identity, Binary Authorization, Shielded Nodes
- `terraform/vpc.tf` — private subnet, Cloud Armor WAF blocking XSS + SQLi (OWASP rule set)
- `terraform/kms.tf` — KMS envelope encryption, 90-day key rotation, `prevent_destroy` guard

> *"Real Terraform — would apply against GCP as-is. Demonstrated with `terraform plan` to
> avoid live cloud spend. Binary Authorization here is the GCP-native equivalent of the
> Kyverno verifyImages policy: only attested images admitted. KMS + 90-day rotation covers
> PCI-DSS Requirement 3. The `prevent_destroy` lifecycle guard means a `terraform destroy`
> cannot accidentally delete live encryption keys."*

---

### 12. Supply chain integrity — SBOM + signing + admission gate

Open `.github/workflows/ci.yaml` and `.github/workflows/supply-chain.yaml` together.

**The chain:**
1. **syft** — generates SPDX SBOM at build time. Answers "do we ship Log4j?" instantly
2. **cosign keyless** — signs the image using the GitHub Actions OIDC token. No long-lived keys
3. **SLSA provenance** — attestation proving *which pipeline workflow* built the image
4. **Kyverno verifyImages** — verifies the signature at admission time; unsigned = rejected

```bash
kubectl apply -f kyverno/policies/verify-images.yaml

# Try to deploy an unsigned image into the protected namespace:
kubectl run unsigned --image=alpine --namespace payments-dev
# Expected: admission webhook denied — image not signed by your pipeline
```

> *"Scanning tells you whether an image has known vulnerabilities. Supply chain integrity
> answers a different question: is the thing running in my cluster actually what I built,
> or did someone tamper with it between build and deploy? Keyless signing uses the pipeline's
> verified GitHub identity — no keys to rotate or leak. The Kyverno gate runs inside the
> cluster and can't be bypassed by pushing directly to the registry. This is the open-source
> equivalent of GCP Binary Authorization — the 'set you apart' bullet in the JD."*

---

### 13. Loki — log aggregation (PLG stack)

```bash
make loki
```

Add Loki as a Grafana data source:
- Grafana → Connections → Data sources → Add → Loki
- URL: `http://loki-stack:3100`

Then query logs alongside metrics in the same dashboard:
```logql
{namespace="payments-dev"} |= "payment.authorised"
{namespace="payments-dev", container="consumer"} | json | line_format "{{.message}}"
```

Apply alert rules:
```bash
make alert-rules
```

Open Grafana → Alerting → Alert rules — you'll see:
- **HPAAtMaxReplicas** — fires if HPA stays at max for 5 minutes
- **PodCrashLooping** — fires after 3 restarts in 15 minutes
- **RabbitMQQueueDepthHigh** — fires when queue > 1000 messages
- **RabbitMQNodeDown** — fires within 1 minute of a broker node going offline

> *"Prometheus gives you metrics. Loki gives you logs. Together in Grafana you get the
> full picture: you see CPU spike in the metric, then correlate it with the exact log
> line that caused it — without switching tools. For PCI-DSS Requirement 10, 30-day
> log retention is configured in both Prometheus and Loki. The AlertManager rules mean
> we know about problems before customers do — which is the stated goal."*

---

### 14. DAST — OWASP ZAP dynamic scan

This runs automatically in GitHub Actions (`.github/workflows/dast.yaml`) on every push
to master and weekly. To understand what it covers:

Open the **Actions tab** on GitHub → **DAST — OWASP ZAP** → download the `zap-report`
artifact → open `report_html.html` in a browser.

The report shows:
- HTTP response headers checked (Content-Security-Policy, X-Frame-Options, HSTS)
- Spider results — all URLs discovered and tested
- Alerts by severity with evidence and remediation guidance

Open `.zap/rules.tsv` — shows which rules are WARN vs IGNORE and why (e.g. HSTS is
ignored because TLS terminates at Istio, not at nginx directly).

> *"SAST and SCA tell you about problems in source code and known CVEs in packages.
> DAST tells you what an attacker actually sees when they hit the running application over
> HTTP. CodeQL won't catch a missing Content-Security-Policy header. ZAP will. Running
> all three — SAST, SCA, DAST — is the complete shift-left picture. The HTML report is
> a CI artifact so every engineer can see what the scanner found on their PR."*

---

### 15. PCI-DSS audit mapping

```bash
cat docs/pci-dss-mapping.md
```

Walk down the table — every PCI-DSS requirement maps to a specific file.

> *"Audit readiness isn't just having the controls — it's pointing an auditor at evidence
> immediately. Signed Git commits in ArgoCD are the change log, Kyverno policies are the
> enforcement evidence, KMS rotation is automatic and logged in Cloud Audit Logs."*

---

## JD mapping

| JD requirement | Where in this repo |
|---|---|
| Production Kubernetes (GKE) | `kind-config.yaml`, `terraform/gke.tf` |
| Terraform for GCP | `terraform/` (plan-validated) |
| CI/CD — Google Cloud Build + GitHub Actions | `cloudbuild.yaml`, `.github/workflows/` |
| DNS, TLS/mTLS, load balancing | Istio mTLS (`istio/`), ingress port mappings |
| Docker / container lifecycle | `Dockerfile`, `k8s/base/deployment.yaml` |
| GitOps — ArgoCD + Kustomize | `argocd/application.yaml`, `k8s/overlays/` |
| Istio / service mesh | `istio/peer-authentication.yaml`, `istio/authorization-policy.yaml` |
| PCI-DSS at infrastructure level | `docs/pci-dss-mapping.md`, Kyverno, NetworkPolicies, KMS |
| GCP: KMS, Cloud Armor, Binary Authorization | `terraform/kms.tf`, `terraform/vpc.tf`, `terraform/gke.tf` |
| Local Kubernetes dev tooling (Tilt) | `Tiltfile` |
| Prometheus + Grafana | `monitoring/values-kube-prometheus-stack.yaml` |
| Snyk AI scanning | `.github/workflows/ci.yaml` — Snyk step |
| Trivy multi-scanner | `.github/workflows/ci.yaml` — Trivy step |
| Supply chain / Binary Authorization | `kyverno/policies/verify-images.yaml`, `.github/workflows/supply-chain.yaml` |
| RabbitMQ async payment flow | `k8s/rabbitmq/` |
| Helm | `charts/nginx-app/` (authored), platform charts (consumed) |

## Note on scope

Runs on a local **kind** cluster by design — the role explicitly values "keeping local
development environments working so engineers can run the full stack on their machines"
and names Tilt. Cloud IaC (`terraform/`) is real and `terraform plan`-validated against
GKE; demonstrated without live cloud spend. Open in GitHub Codespaces to run with zero
local setup.
