# Security Policy

## Supported versions

This is a PoC / interview demonstration repository. There are no versioned releases.

## Reporting a vulnerability

If you discover a security vulnerability in this repository, please report it responsibly.

**Do not open a public GitHub issue for security findings.**

Instead, use GitHub's private vulnerability disclosure:

1. Go to the **Security** tab of this repository
2. Click **Report a vulnerability**
3. Fill in the template with as much detail as you can

You will receive an acknowledgement within 48 hours.

## Scope

- Kubernetes manifests (`k8s/`, `charts/`, `kyverno/`, `istio/`, `argocd/`)
- CI/CD workflows (`.github/workflows/`)
- Infrastructure-as-code (`terraform/`)
- Container image configuration (`Dockerfile`)
- Helm chart (`charts/nginx-app/`)

Out of scope: the underlying upstream projects (nginx, RabbitMQ, Prometheus, etc.) —
report those to their respective maintainers.

## Security controls in this repository

See the security audit section in [README.md](README.md) for a full breakdown of
controls, findings, and framework mappings (NIST CSF, ISO 27001, Cyber Essentials Plus,
OWASP DSOMM).
