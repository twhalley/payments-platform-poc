.PHONY: cluster destroy load-test watch argocd prometheus loki alert-rules \
        rabbitmq kyverno istio falco terraform-plan security-scan kyverno-test \
        verify-supply-chain rbac-audit secrets clean help

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
	@echo ""
	@echo "── Secrets management ──────────────────────────────────────────────────────"
	@echo "  make secrets           Install ESO + OpenBao, seed demo secrets, apply ExternalSecrets"

# ── Phase 1+2: cluster + nginx ────────────────────────────────────────────────
cluster:
	bash scripts/cluster-setup.sh

destroy:
	@if [ "$${CODESPACES:-}" = "true" ]; then \
		kind delete cluster --name payments-poc; \
	else \
		sudo KIND_EXPERIMENTAL_PROVIDER=podman kind delete cluster --name payments-poc; \
	fi

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
# NOTE: Falco modern_ebpf requires host kernel BPF access.
# It works on local bare-metal/VM but NOT inside GitHub Codespaces (nested container).
# In Codespaces, explain it via the README Step 10 walkthrough and securityContext hardening.
falco:
	@if [ "$${CODESPACES:-}" = "true" ]; then \
		echo ""; \
		echo "Falco skipped: modern_ebpf requires direct kernel access (not available in Codespaces)."; \
		echo ""; \
		echo "For the interview, explain Falco via:"; \
		echo "  - README Step 10: what Falco detects and how (shell spawn, /etc writes, IMDS probe)"; \
		echo "  - k8s/base/deployment.yaml securityContext: what Kyverno + PSS prevent at admission"; \
		echo "  - monitoring/alert-rules.yaml: what AlertManager fires on at runtime"; \
		echo "  These together cover prevention (Kyverno/PSS) + detection (Falco) + alerting (AlertManager)"; \
	else \
		helm repo add falcosecurity https://falcosecurity.github.io/charts --force-update 2>/dev/null; \
		helm upgrade --install falco falcosecurity/falco \
			--namespace falco --create-namespace \
			--set driver.kind=modern_ebpf \
			--set falco.grpc.enabled=true \
			--set falco.grpcOutput.enabled=true \
			--wait; \
		echo ""; \
		echo "Falco ready. Watch runtime alerts:"; \
		echo "  kubectl logs -n falco -l app.kubernetes.io/name=falco -f"; \
	fi

# ── Phase 6: Terraform plan (no cloud spend) ──────────────────────────────────
terraform-plan:
	cd terraform && terraform init -upgrade && terraform plan -var-file=../example.tfvars

# ── Run everything ─────────────────────────────────────────────────────────────
# Falco is attempted last — it prints a friendly skip message in Codespaces
# rather than failing the whole target.
all: cluster argocd prometheus loki alert-rules rabbitmq kyverno istio falco
	@echo ""
	@echo "Full stack deployed."
	@echo "Terminal 1: make watch"
	@echo "Terminal 2: make load-test"

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

# ── Phase 17: Secrets management ─────────────────────────────────────────────
# Installs External Secrets Operator + OpenBao (open-source Vault fork) in-cluster,
# seeds demo secrets, then applies the ExternalSecrets that pull them into K8s Secrets.
#
# Local/Codespaces: OpenBao dev mode — in-memory, auto-unseal, root token = "root"
# Production (GKE): swap secret-store.yaml for gcp-secret-store.yaml (Workload Identity)
#                   GCP Secret Manager resources provisioned by terraform/secrets.tf
#
# After this target, verify with:
#   kubectl get externalsecret -n payments-dev
#   kubectl get secret payment-gateway-key db-credentials -n payments-dev
secrets:
	@echo "── Installing External Secrets Operator..."
	helm repo add external-secrets https://charts.external-secrets.io --force-update 2>/dev/null
	helm upgrade --install external-secrets external-secrets/external-secrets \
		--namespace external-secrets --create-namespace \
		--set installCRDs=true \
		--wait

	@echo ""
	@echo "── Installing OpenBao (open-source Vault fork)..."
	helm repo add openbao https://openbao.github.io/openbao-helm --force-update 2>/dev/null
	helm upgrade --install openbao openbao/openbao \
		--namespace openbao --create-namespace \
		--values k8s/secrets/openbao-values.yaml \
		--wait

	@echo ""
	@echo "── Storing OpenBao root token in ESO's namespace..."
	kubectl create namespace payments-dev 2>/dev/null || true
	kubectl create secret generic openbao-token \
		--namespace external-secrets \
		--from-literal=token=root \
		--dry-run=client -o yaml | kubectl apply -f -

	@echo ""
	@echo "── Port-forwarding OpenBao for secret seeding..."
	kubectl port-forward -n openbao svc/openbao 8200:8200 &
	sleep 3

	@echo ""
	@echo "── Seeding demo secrets into OpenBao..."
	OPENBAO_ADDR=http://127.0.0.1:8200 OPENBAO_TOKEN=root bash scripts/seed-secrets.sh

	@echo ""
	@echo "── Applying ESO ClusterSecretStore and ExternalSecrets..."
	kubectl apply -f k8s/secrets/secret-store.yaml
	kubectl apply -f k8s/secrets/external-secret.yaml

	@echo ""
	@echo "── Waiting for secrets to sync (up to 60s)..."
	sleep 10
	kubectl get externalsecret -n payments-dev
	kubectl get secret payment-gateway-key db-credentials -n payments-dev 2>/dev/null || \
		echo "Secrets not yet synced — run: kubectl describe externalsecret -n payments-dev"

	@echo ""
	@echo "Secrets layer ready."
	@echo "  OpenBao UI:  not enabled (dev mode)"
	@echo "  ESO status:  kubectl get clustersecretstore"
	@echo "  In GKE:      swap secret-store.yaml for k8s/secrets/gcp-secret-store.yaml"
	@echo "               (terraform/secrets.tf provisions the GCP resources)"

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
