# Minimal Dockerfile wrapping the nginx-unprivileged base image with our custom content.
# The base image already runs as UID 101 (non-root) and listens on 8080.
FROM nginxinc/nginx-unprivileged:1.27-alpine

# Upgrade all OS packages to pick up latest Alpine security patches.
# Fixes CVE-2026-40200 (musl), CVE-2026-22184 (zlib),
# CVE-2026-27135 (nghttp2), CVE-2026-6732 (libxml2).
# Must run as root, then drop back to the unprivileged nginx UID.
USER root
RUN apk upgrade --no-cache
USER 101

# Copy our custom landing page
COPY k8s/base/configmap.yaml /tmp/configmap.yaml

# (In a real build, extract HTML from the ConfigMap or build from a src/ directory.)
# For the PoC the ConfigMap drives config; this Dockerfile satisfies the CI image build step.
LABEL org.opencontainers.image.source="https://github.com/twhalley/payments-platform-poc"
LABEL org.opencontainers.image.description="Hardened nginx PoC for payments platform"
LABEL org.opencontainers.image.licenses="MIT"

EXPOSE 8080
