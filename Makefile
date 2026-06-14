.PHONY: cluster destroy load-test watch argocd prometheus loki alert-rules \
        rabbitmq kyverno istio falco terraform-plan clean help

NAMESPACE  := payments-dev
KUBECONFIG ?= $(HOME)/.kube/config

help:
	@echo "payments-platform-poc — available targets:"
	@echo ""
	@echo "  make cluster        Bootstrap kind cluster and deploy nginx (Phases 1-2)"
	@echo "  make watch          Watch HPA + pods in real time (open before load-test)"
	@echo "  make load-test      Fire k6 load at nginx — triggers HPA scale-out"
	@echo "  make argocd         Install ArgoCD and register the GitOps Application"
	@echo "  make prometheus     Install Prometheus + Grafana"
	@echo "  make rabbitmq       Install RabbitMQ + start producer/consumer"
	@echo "  make kyverno        Install Kyverno + apply all admission policies"
	@echo "  make istio          Install Istio + apply mTLS + AuthorizationPolicy"
	@echo "  make falco          Install Falco runtime threat detection"
	@echo "  make loki           Install Loki + Promtail log aggregation"
	@echo "  make alert-rules    Apply Prometheus AlertManager alert rules"
	@echo "  make terraform-plan Validate GCP/GKE IaC with terraform plan"
	@echo "  make destroy        Tear down the kind cluster"
	@echo "  make all            Run everything (cluster → all platform components)"

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
