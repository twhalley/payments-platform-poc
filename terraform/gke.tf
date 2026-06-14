# GKE cluster — private nodes, Workload Identity, Binary Authorization.
resource "google_container_cluster" "payments" {
  provider = google-beta
  name     = var.cluster_name
  location = var.region

  # Use a separately managed node pool
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.payments_vpc.name
  subnetwork = google_compute_subnetwork.gke_subnet.name

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes    = true    # nodes have no external IPs
    enable_private_endpoint = false   # keep API server reachable for demo
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # Workload Identity: pods authenticate to GCP APIs via GSA, not node SA keys
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Binary Authorization: only admit images with a valid attestation
  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  # Dataplane V2 (eBPF-based, enables NetworkPolicy enforcement)
  datapath_provider = "ADVANCED_DATAPATH"

  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }

  release_channel {
    channel = "REGULAR"
  }

  maintenance_policy {
    recurring_window {
      start_time = "2024-01-01T02:00:00Z"
      end_time   = "2024-01-01T06:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA"
    }
  }

  # Shielded nodes — protect against rootkit-level compromise
  enable_shielded_nodes = true
}

resource "google_container_node_pool" "primary" {
  name     = "primary"
  cluster  = google_container_cluster.payments.name
  location = var.region

  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.node_machine_type
    disk_size_gb = 50
    disk_type    = "pd-ssd"

    # Workload Identity on nodes
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }
}
