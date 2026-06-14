# INTENTIONALLY VULNERABLE — demo/negative test case only.
# DO NOT use this image in any environment.
#
# Purpose: show Trivy catching CVEs at build time before the image reaches a registry.
# nginx 1.14.0 has ~40 known CVEs including buffer overflows and remote code execution.
#
# Negative demo (run from repo root):
#   docker build -f demo/vulnerable/Dockerfile -t demo-vulnerable .
#   trivy image demo-vulnerable
#   # Expected: CRITICAL and HIGH CVEs across nginx, OpenSSL, zlib
#
# Positive contrast:
#   trivy image nginxinc/nginx-unprivileged:1.27-alpine
#   # Expected: 0 CRITICAL, 0 HIGH
#
# The CI pipeline (.github/workflows/ci.yaml) uses exit-code: "1" on CRITICAL/HIGH.
# This image would fail the build — it never reaches GHCR.
FROM nginx:1.14.0
