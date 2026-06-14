# Cloud KMS — envelope encryption for secrets and etcd data at rest.
# Maps to PCI-DSS Requirement 3 (protect stored account data).
resource "google_kms_key_ring" "payments" {
  name     = var.kms_keyring
  location = var.region
}

resource "google_kms_crypto_key" "etcd" {
  name            = "etcd-encryption"
  key_ring        = google_kms_key_ring.payments.id
  rotation_period = "7776000s"   # 90-day rotation

  lifecycle {
    prevent_destroy = true   # never accidentally delete live encryption keys
  }
}

resource "google_kms_crypto_key" "secrets" {
  name            = "app-secrets"
  key_ring        = google_kms_key_ring.payments.id
  rotation_period = "7776000s"
}

# Allow GKE service account to use the etcd key
data "google_project" "current" {}

resource "google_kms_crypto_key_iam_member" "gke_etcd" {
  crypto_key_id = google_kms_crypto_key.etcd.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.current.number}@container-engine-robot.iam.gserviceaccount.com"
}
