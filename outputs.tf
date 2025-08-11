output "gcp_service_account_email" {
  description = "The email of the GCP service account."
  value       = google_service_account.stackgres_sa.email
}

output "gke_cluster_name_output" {
  description = "The name of the created GKE cluster."
  value       = google_container_cluster.gke_timescale_db_cluster.name
}