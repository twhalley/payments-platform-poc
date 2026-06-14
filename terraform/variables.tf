variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for all resources"
  type        = string
  default     = "europe-west2"   # London — low-latency for UK payments
}

variable "zone" {
  type    = string
  default = "europe-west2-a"
}

variable "cluster_name" {
  type    = string
  default = "payments-poc"
}

variable "node_machine_type" {
  description = "GKE node machine type"
  type        = string
  default     = "e2-standard-4"
}

variable "min_node_count" {
  type    = number
  default = 1
}

variable "max_node_count" {
  type    = number
  default = 5
}

variable "kms_keyring" {
  description = "Cloud KMS keyring name for secret/disk encryption"
  type        = string
  default     = "payments-poc-keyring"
}
