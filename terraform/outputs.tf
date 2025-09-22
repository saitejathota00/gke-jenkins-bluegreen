output "cluster_name" { value = google_container_cluster.gke.name }
output "zone" { value = var.zone }
output "region" { value = var.region }
output "repo" { value = google_artifact_registry_repository.repo.repository_id }

