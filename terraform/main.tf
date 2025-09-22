terraform {
  # Backend configured by GitHub Actions with -backend-config
  backend "gcs" {}

  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.40"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.40"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# ----------------------
# Networking: dedicated VPC + subnet with secondary ranges (VPC-native GKE)
# ----------------------
resource "google_compute_network" "vpc" {
  name                    = "${var.name}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${var.name}-subnet"
  ip_cidr_range = "10.10.0.0/16"
  region        = var.region
  network       = google_compute_network.vpc.id

  # Secondary ranges for Pods & Services (alias IPs)
  secondary_ip_range {
    range_name    = "${var.name}-pods"
    ip_cidr_range = "10.20.0.0/14"
  }
  secondary_ip_range {
    range_name    = "${var.name}-services"
    ip_cidr_range = "10.24.0.0/20"
  }
}

# ----------------------
# GKE cluster (ZONAL to keep total nodes = 2)
# ----------------------
resource "google_container_cluster" "gke" {
  provider   = google-beta
  name       = "${var.name}-gke"
  location   = var.zone # ZONAL cluster (cost-safe)
  network    = google_compute_network.vpc.self_link
  subnetwork = google_compute_subnetwork.subnet.self_link

  remove_default_node_pool = true
  initial_node_count       = 1

  release_channel {
    channel = "REGULAR"
  }

  # VPC-native (alias IPs) wired to our secondary ranges
  ip_allocation_policy {
    cluster_secondary_range_name  = "${var.name}-pods"
    services_secondary_range_name = "${var.name}-services"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS", "APISERVER"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "APISERVER", "SCHEDULER", "CONTROLLER_MANAGER"]
  }
}

# Dedicated node pool: 2 nodes, autoscaling 2..5, Shielded VM
resource "google_container_node_pool" "pool" {
  provider = google-beta
  name     = "${var.name}-pool"
  location = var.zone
  cluster  = google_container_cluster.gke.name

  initial_node_count = 2

  autoscaling {
    min_node_count = 2
    max_node_count = 5
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.node_machine_type
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    labels = { env = var.name }

    metadata = { disable-legacy-endpoints = "true" }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
}

# Artifact Registry (handy later if you build/push images)
resource "google_artifact_registry_repository" "repo" {
  location      = var.region
  repository_id = "${var.name}-repo"
  description   = "Images for demo"
  format        = "DOCKER"
}

