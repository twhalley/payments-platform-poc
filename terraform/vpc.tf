# VPC with private GKE subnet + secondary ranges for pods/services.
# Separate subnet isolates the CDE (card-data environment) — PCI-DSS Req 1.
resource "google_compute_network" "payments_vpc" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "gke_subnet" {
  name          = "${var.cluster_name}-gke-subnet"
  ip_cidr_range = "10.10.0.0/20"
  region        = var.region
  network       = google_compute_network.payments_vpc.id

  private_ip_google_access = true   # nodes reach Google APIs without external IPs

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.20.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.30.0.0/20"
  }

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Cloud Armor security policy — WAF in front of external load balancer
resource "google_compute_security_policy" "payments_waf" {
  name = "${var.cluster_name}-waf"

  rule {
    action   = "deny(403)"
    priority = 1000
    match {
      expr {
        # Block OWASP top 10 (pre-configured rule set)
        expression = "evaluatePreconfiguredExpr('xss-stable') || evaluatePreconfiguredExpr('sqli-stable')"
      }
    }
    description = "Block XSS and SQLi"
  }

  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow"
  }
}
