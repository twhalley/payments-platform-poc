.PHONY: cluster destroy load-test watch argocd prometheus loki alert-rules \
        rabbitmq kyverno istio falco terraform-plan security-scan kyverno-test \
        verify-supply-chain rbac-audit clean help

NAMESPACE  := payments-dev
KUBECONFIG ?= $(HOME)/.kube/config

help:
	@echo "payments-platform-poc — available targets:"
	@echo ""
	@echo "── Platform ────────────────────────────────────────────────────────────"
	@echo "  make cluster           Bootstrap kind cluster and deploy nginx (Phases 1-2)"
	@echo "  make watch             Watch HPA + pods in real time (open before load-test)"
	@echo "  make load-test         Fire k6 load at nginx — triggers HPA scale-out"
	@echo "  make argocd            Install ArgoCD and register the GitOps Application"
	@echo "  make prometheus        Install Prometheus + Grafana"
	@echo "  make rabbitmq          Install RabbitMQ + start producer/consumer"
	@echo "  make kyverno           Install Kyverno + apply all admission policies"
	@echo "  make istio             Install Istio + apply mTLS + AuthorizationPolicy"
	@echo "  make falco             Install Falco runtime threat detection"
	@echo "  make loki              Install Loki + Promtail log aggregation"
	@echo "  make alert-rules       Apply Prometheus AlertManager alert rules"
	@echo "  make terraform-plan    Validate GCP/GKE IaC with terraform plan"
	@echo "  make destroy           Tear down the kind cluster"
	@echo "  make all               Run everything (cluster → all platform components)"
	@echo ""
	@echo "── Security demos (no cluster required) ────────────────────────────────"
	@echo "  make security-scan     Run all local scanners: secrets + CVE + IaC misconfigs"
	@echo "  make kyverno-test      Unit-test Kyverno policies without a cluster"
	@echo "  make rbac-audit        Show what each service account can and cannot do"
	@echo "  make verify-supply-chain  Verify cosign signature on the latest pushed image"

# ── Phase 1+2: cluster + nginx ────────────────────────────────────────────────
cluster:
	bash scripts/cluster-setup.sh

destroy:
	sudo KIND_EXPERIMENTAL_PROVIDER=podman kind delete cluster --name payments-poc

# ── HPA demo ──────────────────────────────────────────────────────────────────
watch:
	kubectl get hpa,pods -n $(NAMESPACE) -w

load-test:
	@echo "Port-forwarding nginx to localhost:8080..."
	kubectl port-forward -n $(NAMESPACE) svc/dev-nginx-app 8080:80 &
	@sleep 2
	k6 run -e TARGET_URL=http://localhost:8080 \
		--summary-export=k6-summary.json \
		scripts/load-test.js
	@echo ""
	@echo "Summary written to k6-summary.json"

# ── Phase 3: ArgoCD ───────────────────────────────────────────────────────────
argocd:
	helm repo add argo https://argoproj.github.io/argo-helm --force-update 2>/dev/null
	helm upgrade --install argocd argo/argo-cd \
		--namespace argocd \
		--values argocd/values-argocd.yaml \
		--wait
	kubectl apply -f argocd/application.yaml
	@echo ""
	@echo "ArgoCD ready. Open the UI:"
	@echo "  kubectl port-forward -n argocd svc/argocd-server 8443:443"
	@echo "  https://localhost:8443"

# ── Phase 5: Prometheus + Grafana ─────────────────────────────────────────────
prometheus:
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update 2>/dev/null
	helm upgrade --install kube-prometheus-stack \
		prometheus-community/kube-prometheus-stack \
		--namespace monitoring --create-namespace \
		--values monitoring/values-kube-prometheus-stack.yaml \
		--set grafana.adminPassword=poc-admin \
		--wait
	@echo ""
	@echo "Grafana ready. Open the UI:"
	@echo "  kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
	@echo "  http://localhost:3000  admin / poc-admin"

# ── Phase 8: RabbitMQ ─────────────────────────────────────────────────────────
rabbitmq:
	helm repo add bitnami https://charts.bitnami.com/bitnami --force-update 2>/dev/null
	helm upgrade --install rabbitmq bitnami/rabbitmq \
		--namespace $(NAMESPACE) \
		--values k8s/rabbitmq/values-rabbitmq.yaml \
		--wait
	kubectl create secret generic rabbitmq-url \
		--namespace $(NAMESPACE) \
		--from-literal=url="amqp://payments:poc-change-me@rabbitmq.$(NAMESPACE).svc:5672/payments" \
		--dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -f k8s/rabbitmq/networkpolicy.yaml
	kubectl apply -f k8s/rabbitmq/pdb.yaml
	kubectl apply -f k8s/rabbitmq/consumer-deployment.yaml
	kubectl apply -f k8s/rabbitmq/producer-job.yaml
	@echo ""
	@echo "RabbitMQ ready. Management UI:"
	@echo "  kubectl port-forward -n $(NAMESPACE) svc/rabbitmq 15672:15672"
	@echo "  http://localhost:15672  payments / poc-change-me"

# ── Phase 7: Kyverno ──────────────────────────────────────────────────────────
kyverno:
	helm repo add kyverno https://kyverno.github.io/kyverno --force-update 2>/dev/null
	helm upgrade --install kyverno kyverno/kyverno \
		--namespace kyverno --create-namespace \
		--wait
	kubectl apply -f kyverno/policies/require-non-root.yaml
	kubectl apply -f kyverno/policies/require-resource-limits.yaml
	kubectl apply -f kyverno/policies/block-privileged.yaml
	@echo ""
	@echo "Kyverno ready. Test policy enforcement:"
	@echo "  kubectl run bad-pod --image=nginx --namespace $(NAMESPACE)"
	@echo "  # Expected: admission webhook denied"

# ── Phase 7: Istio mTLS ───────────────────────────────────────────────────────
istio:
	helm repo add istio https://istio-release.storage.googleapis.com/charts --force-update 2>/dev/null
	helm upgrade --install istio-base istio/base \
		--namespace istio-system --create-namespace --wait
	helm upgrade --install istiod istio/istiod \
		--namespace istio-system --wait
	kubectl apply -f istio/peer-authentication.yaml
	kubectl apply -f istio/authorization-policy.yaml
	@echo "Istio installed — mTLS STRICT enforced in $(NAMESPACE)"

# ── Loki log aggregation ──────────────────────────────────────────────────────
loki:
	helm repo add grafana https://grafana.github.io/helm-charts --force-update 2>/dev/null
	helm upgrade --install loki-stack grafana/loki-stack \
		--namespace monitoring --create-namespace \
		--values monitoring/values-loki-stack.yaml \
		--wait
	@echo ""
	@echo "Loki ready. Add data source in Grafana:"
	@echo "  URL: http://loki-stack:3100"
	@echo "  Then use LogQL to query: {namespace=\"payments-dev\"}"

# ── AlertManager rules ────────────────────────────────────────────────────────
alert-rules:
	kubectl apply -f monitoring/alert-rules.yaml
	@echo "Alert rules applied. View in Grafana → Alerting → Alert rules"

# ── Phase 12: Falco runtime security ──────────────────────────────────────────
falco:
	helm repo add falcosecurity https://falcosecurity.github.io/charts --force-update 2>/dev/null
	helm upgrade --install falco falcosecurity/falco \
		--namespace falco --create-namespace \
		--set driver.kind=modern_ebpf \
		--set falco.grpc.enabled=true \
		--set falco.grpcOutput.enabled=true \
		--wait
	@echo ""
	@echo "Falco ready. Watch runtime alerts:"
	@echo "  kubectl logs -n falco -l app.kubernetes.io/name=falco -f"

# ── Phase 6: Terraform plan (no cloud spend) ──────────────────────────────────
terraform-plan:
	cd terraform && terraform init -upgrade && terraform plan -var-file=../example.tfvars

# ── Run everything ─────────────────────────────────────────────────────────────
all: cluster argocd prometheus loki alert-rules rabbitmq kyverno istio falco
	@echo ""
	@echo "Full stack deployed. Run 'make load-test' in one terminal and 'make watch' in another."

# ── Security scan (local — no cluster required) ────────────────────────────────
# Runs four Trivy scan modes plus the vulnerable/hardened image comparison.
# Quick entry point to demonstrate the shift-left scanning layer at interview.
security-scan:
	@echo "═══ 1/5  Trivy: hardcoded secrets in source code ════════════════════════"
	trivy fs --scanners secret --severity CRITICAL,HIGH .
	@echo ""
	@echo "═══ 2/5  Trivy: IaC misconfigurations (k8s + terraform) ════════════════"
	trivy fs --scanners misconfig --severity HIGH,CRITICAL k8s/ terraform/ || true
	@echo ""
	@echo "═══ 3/5  Trivy: production image (expect 0 findings) ════════════════════"
	trivy image --severity CRITICAL,HIGH nginxinc/nginx-unprivileged:1.27-alpine
	@echo ""
	@echo "═══ 4/5  Trivy: vulnerable demo image (expect many CVEs) ════════════════"
	docker build -q -f demo/vulnerable/Dockerfile -t demo-vulnerable . 2>/dev/null || true
	trivy image --severity CRITICAL,HIGH demo-vulnerable || true
	@echo ""
	@echo "═══ 5/5  syft + grype: SBOM + CVE query without rebuilding ══════════════"
	@command -v syft  >/dev/null || (echo "syft not installed — skipping SBOM step"; exit 0)
	@command -v grype >/dev/null || (echo "grype not installed — skipping SBOM step"; exit 0)
	syft nginxinc/nginx-unprivileged:1.27-alpine -o spdx-json > /tmp/prod-sbom.json 2>/dev/null
	grype sbom:/tmp/prod-sbom.json --fail-on critical || true
	@echo ""
	@echo "Security scan complete. See demo/insecure-code/ for SAST examples."

# ── Kyverno policy unit tests (no cluster required) ───────────────────────────
# Tests policies against known-good and known-bad pods defined in kyverno/tests/.
# Validates that policies actually catch what they claim to catch.
kyverno-test:
	@echo "Running Kyverno policy unit tests..."
	kyverno test kyverno/
	@echo ""
	@echo "All policies validated. Good pods pass; bad pods fail as expected."

# ── RBAC audit ────────────────────────────────────────────────────────────────
# Shows least-privilege in action: what each service account can and cannot do.
rbac-audit:
	@echo "── nginx-app service account (no API access) ────────────────────────────"
	kubectl auth can-i create pods      -n payments-dev --as system:serviceaccount:payments-dev:nginx-app || true
	kubectl auth can-i get  secrets     -n payments-dev --as system:serviceaccount:payments-dev:nginx-app || true
	kubectl auth can-i list deployments -n payments-dev --as system:serviceaccount:payments-dev:nginx-app || true
	@echo ""
	@echo "── argocd deployer (deploy only, no delete) ─────────────────────────────"
	kubectl auth can-i patch  deployments -n payments-dev --as system:serviceaccount:argocd:argocd-application-controller
	kubectl auth can-i delete deployments -n payments-dev --as system:serviceaccount:argocd:argocd-application-controller || true
	kubectl auth can-i get    secrets     -n payments-dev --as system:serviceaccount:argocd:argocd-application-controller || true

# ── Verify supply chain ───────────────────────────────────────────────────────
# Confirms the latest pushed image carries a valid cosign keyless signature.
# Requires: image pushed to GHCR via the CI pipeline (make sure CI has run on master).
verify-supply-chain:
	@echo "Verifying cosign signature on latest image..."
	cosign verify \
		--certificate-identity-regexp "https://github.com/twhalley/.*" \
		--certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
		ghcr.io/twhalley/payments-platform-poc/nginx-app:$(shell git rev-parse HEAD 2>/dev/null || echo "latest") \
		| jq '.[0] | {subject: .optional.Subject, issuer: .optional.Issuer, workflow: .optional.githubWorkflowName}'
