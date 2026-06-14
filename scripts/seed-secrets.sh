#!/usr/bin/env bash
# seed-secrets.sh — initialise OpenBao KV v2 and seed demo secrets.
#
# Called by `make secrets` after OpenBao is installed.
# Uses `bao` CLI (OpenBao's drop-in Vault replacement) via port-forward.
#
# WHY: The ExternalSecrets in k8s/secrets/external-secret.yaml expect these
# exact paths in OpenBao. Without seeding, ESO will report SecretSyncFailed.
#
# PRODUCTION EQUIVALENT:
#   In GKE, secrets are created once via:
#     gcloud secrets versions add payment-gateway-key --data-file=<(echo -n "$VALUE")
#   Terraform manages the secret resources; CI or a human adds the actual values.

set -euo pipefail

OPENBAO_ADDR="${OPENBAO_ADDR:-http://127.0.0.1:8200}"
OPENBAO_TOKEN="${OPENBAO_TOKEN:-root}"

# Wait for OpenBao to be ready (pod may still be starting)
echo "── Waiting for OpenBao to be ready..."
for i in $(seq 1 30); do
  if curl -sf "${OPENBAO_ADDR}/v1/sys/health?standbyok=true" >/dev/null 2>&1; then
    echo "   OpenBao is up."
    break
  fi
  echo "   Attempt ${i}/30 — retrying in 2s..."
  sleep 2
done

export VAULT_ADDR="${OPENBAO_ADDR}"
export VAULT_TOKEN="${OPENBAO_TOKEN}"

# Enable KV v2 at path 'secret' (dev mode enables it automatically, but be explicit)
echo ""
echo "── Enabling KV v2 secrets engine..."
bao secrets enable -path=secret kv-v2 2>/dev/null || echo "   (already enabled — skipping)"

# Seed payment gateway key
# In production this value comes from the real gateway provider, stored in GCP Secret Manager.
echo ""
echo "── Seeding payments/gateway (api_key)..."
bao kv put secret/payments/gateway \
  api_key="poc-demo-gateway-key-$(openssl rand -hex 8)"

# Seed database credentials
echo ""
echo "── Seeding payments/database (password + host)..."
bao kv put secret/payments/database \
  password="poc-demo-db-$(openssl rand -hex 8)" \
  host="postgresql.payments-dev.svc.cluster.local"

echo ""
echo "── Verifying secrets are readable..."
bao kv get secret/payments/gateway
bao kv get secret/payments/database

echo ""
echo "Secrets seeded. ESO will now sync these into K8s Secrets:"
echo "  kubectl get externalsecret -n payments-dev"
echo "  kubectl get secret payment-gateway-key db-credentials -n payments-dev"
