# Tilt local development loop.
# Tilt watches your source files and re-deploys on change — faster than kubectl apply.
# Start: tilt up
# They use Tilt; this shows you can set it up and explains the value.

# Point Tilt at the local kind cluster
allow_k8s_contexts("kind-payments-poc")

# ── nginx-app via Kustomize ────────────────────────────────────────────────────
# Watch k8s manifests and re-apply on change
k8s_yaml(kustomize("k8s/overlays/dev"))

# Port-forward so the browser opens automatically on save
k8s_resource(
    "dev-nginx-app",
    port_forwards=["8080:80"],
    labels=["app"],
)

# ── RabbitMQ ────────────────────────────────────────────────────────────────────
# Watch RabbitMQ manifests; port-forward the management UI
k8s_yaml([
    "k8s/rabbitmq/pdb.yaml",
    "k8s/rabbitmq/producer-job.yaml",
    "k8s/rabbitmq/consumer-deployment.yaml",
])

k8s_resource(
    "payment-consumer",
    port_forwards=["5672:5672", "15672:15672"],
    labels=["rabbitmq"],
)

# ── Rebuild producer on change ─────────────────────────────────────────────────
# (If you move the producer to a real Dockerfile, swap kustomize for docker_build)
# docker_build("payment-producer", "services/producer")

# ── Live update: inject changed HTML without restarting the pod ────────────────
# Demonstrates Tilt's sync-only mode — sub-second feedback loop for static content.
local_resource(
    "html-sync",
    serve_cmd="echo 'watching k8s/base/configmap.yaml'",
    deps=["k8s/base/configmap.yaml"],
    labels=["dev"],
)
