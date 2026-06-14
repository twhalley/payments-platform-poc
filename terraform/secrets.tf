# GCP Secret Manager — production secrets for the payments platform.
# These Terraform resources are the production equivalent of the OpenBao dev mode used in Codespaces.
#
# What this provisions:
#   - Two Secret Manager secrets (payment gateway key + DB password)
#   - A GCP ServiceAccount for the External Secrets Operator (ESO)
#   - Workload Identity binding: ESO's K8s SA → this GCP SA
#   - IAM: GCP SA gets secretmanager.secretAccessor on exactly these secrets (least-privilege)
#   - KMS CMEK encryption for secrets at rest
#
# In Codespaces: OpenBao dev mode (k8s/secrets/openbao-values.yaml) plays this role.
# In GKE production: apply k8s/secrets/gcp-secret-store.yaml instead of secret-store.yaml.
# ExternalSecret manifests (k8s/secrets/external-secret.yaml) are IDENTICAL in both environments.

locals {
  secrets = {
    "payment-gateway-key" = {
      description = "Payment gateway API key — replaces CWE-798 hardcoded credential"
      pci_req     = "3.5"
    }
    "db-credentials-password" = {
      description = "PostgreSQL password for the payments schema"
      pci_req     = "8.3"
    }
    "db-credentials-host" = {
      description = "PostgreSQL host FQDN — avoids hardcoding connection strings"
      pci_req     = "1.3"
    }
  }
}

# ── GCP Secret Manager secrets ────────────────────────────────────────────────
resource "google_secret_manager_secret" "payments" {
  for_each  = local.secrets
  project   = var.project_id
  secret_id = each.key

  labels = {
    managed-by  = "terraform"
    environment = var.environment
    pci-dss-req = each.value.pci_req
  }

  replication {
    user_managed {
      replicas {
        location = var.region
        customer_managed_encryption {
          # Re-uses the KMS key from terraform/main.tf (90-day rotation, PCI-DSS Req 3.6)
          kms_key_name = google_kms_crypto_key.payments_key.id
        }
      }
    }
  }
}

# ── GCP ServiceAccount for External Secrets Operator ─────────────────────────
# ESO runs in K8s with this identity — no JSON key file required (Workload Identity)
resource "google_service_account" "eso" {
  project      = var.project_id
  account_id   = "external-secrets-sa"
  display_name = "External Secrets Operator — payments-platform"
  description  = "Least-privilege SA for ESO to read Secret Manager secrets"
}

# Grant secretAccessor on each individual secret (not project-wide secretAccessor)
resource "google_secret_manager_secret_iam_member" "eso_access" {
  for_each  = local.secrets
  project   = var.project_id
  secret_id = google_secret_manager_secret.payments[each.key].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.eso.email}"
}

# Workload Identity: allows the K8s ServiceAccount in namespace external-secrets
# to impersonate the GCP SA above. No JSON keys — GKE metadata server issues short-lived tokens.
resource "google_service_account_iam_member" "eso_workload_identity" {
  service_account_id = google_service_account.eso.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[external-secrets/external-secrets-sa]"
}

# ── Outputs consumed by the ClusterSecretStore YAML ───────────────────────────
output "eso_gcp_service_account_email" {
  description = "GCP SA email — annotate the ESO K8s ServiceAccount with this value"
  value       = google_service_account.eso.email
}

output "secret_manager_secrets" {
  description = "Secret resource names — use as remoteRef.key in ExternalSecret manifests"
  value       = { for k, v in google_secret_manager_secret.payments : k => v.name }
}
