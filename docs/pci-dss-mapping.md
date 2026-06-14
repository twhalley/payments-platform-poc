# PCI-DSS Infrastructure Mapping

This document maps PCI-DSS v4.0 requirements to controls implemented in this PoC.
Use as an audit-readiness reference when walking through the repo with reviewers.

| PCI-DSS Requirement | Control in this PoC | File(s) |
|---|---|---|
| **Req 1** — Network security controls | NetworkPolicy default-deny + explicit allow; VPC with private subnets | `k8s/base/networkpolicy.yaml`, `terraform/vpc.tf` |
| **Req 1** — WAF | Cloud Armor security policy with OWASP rule set | `terraform/vpc.tf` |
| **Req 2** — Secure configurations | Kyverno policies (non-root, no privilege escalation, resource limits); securityContext on all containers | `kyverno/policies/`, `k8s/base/deployment.yaml` |
| **Req 3** — Protect stored data | Cloud KMS envelope encryption for etcd and app secrets; 90-day key rotation | `terraform/kms.tf` |
| **Req 4** — Encrypt data in transit | Istio mTLS STRICT mode across all service-to-service communication | `istio/peer-authentication.yaml` |
| **Req 6** — Secure systems and software | Snyk + Trivy + CodeQL in CI; Kyverno blocks privileged containers | `.github/workflows/ci.yaml`, `kyverno/policies/block-privileged.yaml` |
| **Req 7** — Restrict access by business need | Istio AuthorizationPolicy deny-all + explicit allow; RBAC least-privilege | `istio/authorization-policy.yaml`, `k8s/rbac/rbac.yaml` |
| **Req 8** — Identify users and authenticate | Workload Identity (pods use GSA, not static keys); automountServiceAccountToken: false | `terraform/gke.tf`, `k8s/rbac/rbac.yaml` |
| **Req 10** — Log and monitor | Prometheus + Grafana; VPC flow logs; Cloud Logging | `monitoring/`, `terraform/vpc.tf` |
| **Req 11** — Test security controls | Snyk + Trivy scan on every PR; supply chain verification gate (Kyverno verifyImages) | `.github/workflows/ci.yaml`, `kyverno/policies/verify-images.yaml` |
| **Req 12** — Audit readiness | ArgoCD audit trail (all changes via Git PR); cosign + SLSA provenance on images; signed commits | `argocd/`, `.github/workflows/supply-chain.yaml` |

## Key talking points

**Why Kustomize for the app but Helm for platform components?**
Kustomize is patch-based with no templating — reviewable diffs, native ArgoCD support.
Helm gives versioned releases and `helm rollback` for third-party software we don't own.

**Why cosign keyless signing rather than long-lived keys?**
Keys are a secret management burden and a leak risk. Keyless signing uses the GitHub
Actions OIDC token — the pipeline's verified identity — so the signature proves *which
pipeline workflow* built the image, with no keys to rotate or protect.

**Why verify images at admission (Kyverno) rather than just in CI?**
CI scanning is a pre-flight check. Admission control is the enforcement gate — it runs
inside the cluster and *cannot be bypassed* by a lateral move that pushes directly to the
registry. Defence in depth.

**How does RabbitMQ fit the payments domain?**
Payment orchestration across dozens of services (authorisation → tokenisation → fraud
check → settlement → CRM) is inherently async. A broker decouples the steps, buffers
traffic spikes, guarantees delivery with acknowledgement + dead-letter queues, and lets
multiple consumers fan out from one event. Losing the settlement service for 30 seconds
doesn't lose the payment — it queues.
