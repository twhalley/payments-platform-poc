# payments-platform-poc

Local-first DevSecOps proof-of-concept for a PCI-DSS payments platform: a GitOps-delivered
Kubernetes workload with autoscaling, layered security scanning, software-supply-chain
integrity enforcement, observability, service-mesh mTLS, and IaC mirroring a GCP/GKE target.

## What it demonstrates
- Kubernetes: probes, resource limits, securityContext, ConfigMaps/Secrets, RBAC,
  NetworkPolicies, Ingress, HPA autoscaling, StatefulSet, PodDisruptionBudget
- Delivery: Kustomize overlays for the app + Helm for platform components (and the app
  packaged as a Helm chart to show both)
- GitOps with ArgoCD (pull-based reconciliation)
- CI/CD in GitHub Actions: build -> Snyk + Trivy + CodeQL -> cosign sign -> manifest bump
- Observability: Prometheus + Grafana (kube-prometheus-stack)
- Istio mTLS, NetworkPolicies and Kyverno policy admission for PCI controls
- Terraform for the GCP/GKE target (plan-validated)
- RabbitMQ broker modelling an async payment-event flow
- Supply chain: SBOM + cosign keyless signing + SLSA provenance + admission-time verification

## Run it locally
<!-- kind quickstart goes here after Phase 1 -->

## JD mapping
<!-- table: each required skill -> where in the repo it lives -->

## Note on scope
Runs on a local kind cluster by design (the role values local dev environments and Tilt).
Cloud IaC is real and terraform-plan-validated against GKE, demonstrated without live spend.
