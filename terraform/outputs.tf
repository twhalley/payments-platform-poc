output "cluster_name" {
  value = google_container_cluster.payments.name
}

output "cluster_endpoint" {
  value     = google_container_cluster.payments.endpoint
  sensitive = true
}

output "kms_keyring_id" {
  value = google_kms_key_ring.payments.id
}

output "vpc_name" {
  value = google_compute_network.payments_vpc.name
}

output "get_credentials_command" {
  description = "Run this to configure kubectl after apply"
  value       = "gcloud container clusters get-credentials ${var.cluster_name} --region ${var.region} --project ${var.project_id}"
}
