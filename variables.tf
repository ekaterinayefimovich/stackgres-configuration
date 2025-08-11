variable "gcp_project_id" {
  description = "The ID of the GCP project."
  type        = string
  default     = "durable-cacao-467313-c7"
}

variable "gcp_service_account_id" {
  description = "The ID for the GCP service account (6-30 chars)."
  type        = string
  default     = "stackgres-backup-sa"
}

variable "gcs_bucket_name" {
  description = "The name for the GCS bucket."
  type        = string
  default     = "backup-timescale-db-of-stackgres"
}

variable "gcs_location" {
  description = "The location for the GCS bucket."
  type        = string
  default     = "EUROPE-WEST3"
}

variable "gke_cluster_name" {
  description = "The name of the GKE cluster to connect to."
  type        = string
  default     = "timescale-db" # <-- Замените на имя вашего кластера
}

variable "gke_cluster_location" {
  description = "The location (zone or region) of the GKE cluster."
  type        = string
  # Для GKE Autopilot рекомендуется использовать регион, а не зону.
  default     = "europe-west3"
}

variable "k8s_namespace" {
  description = "The Kubernetes namespace for StackGres resources."
  type        = string
  default     = "timescale-db-namespace"
}

variable "db_password" {
  description = "The password for the database user."
  type        = string
  sensitive   = true
  default     = "password"
}