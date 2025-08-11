# Providers
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
}

data "google_client_config" "default" {}

provider "kubernetes" {
  host  = "https://${google_container_cluster.gke_timescale_db_cluster.endpoint}"
  token = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.gke_timescale_db_cluster.master_auth[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes = {
    host  = "https://${google_container_cluster.gke_timescale_db_cluster.endpoint}"
    token = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.gke_timescale_db_cluster.master_auth[0].cluster_ca_certificate)
  }
}

# =========================================================
# GOOGLE CLOUD RESOURCES
# =========================================================

# 0. GKE Cluster
resource "google_container_cluster" "gke_timescale_db_cluster" {
  name     = var.gke_cluster_name
  location = var.gke_cluster_location
  enable_autopilot         = true
  workload_identity_config {
    workload_pool = "${var.gcp_project_id}.svc.id.goog"
  }
  deletion_protection = false
}

# 1. Service Account for GCP
resource "google_service_account" "stackgres_sa" {
  account_id   = var.gcp_service_account_id
  display_name = "StackGres Service Account"
}

# 2. IAM for GCS-bucket
resource "google_project_iam_member" "gcs_admin_iam" {
  project = var.gcp_project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.stackgres_sa.email}"
}

# 3. GCS-bucket
resource "google_storage_bucket" "stackgres_backup_bucket" {
  name          = var.gcs_bucket_name
  location      = var.gcs_location
  force_destroy = false
}

# 4. Service Account Key (JSON-file)
resource "google_service_account_key" "stackgres_sa_key" {
  service_account_id = google_service_account.stackgres_sa.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}


# =========================================================
# KUBERNETES RESOURCES
# =========================================================

# Installation StackGres Operator
resource "helm_release" "stackgres_operator" {
  name       = "stackgres-operator"
  repository = "https://stackgres.io/downloads/stackgres-k8s/stackgres/helm/"
  chart      = "stackgres-operator"
  version    = "1.17.0"
  namespace  = "stackgres"
  create_namespace = true
  depends_on       = [google_container_cluster.gke_timescale_db_cluster]
}

# 5. Kubernetes Namescapce
resource "kubernetes_namespace" "timescale_db_namespace" {
  metadata {
    name = var.k8s_namespace
  }
  depends_on = [helm_release.stackgres_operator]
}

# 6. Kubernetes Secret for GCS credentials
resource "kubernetes_secret" "gcp_backup_secret" {
  metadata {
    name      = "gcp-backup-bucket-secret"
    namespace = var.k8s_namespace
  }
  data = {
    "sa-key.json" = base64decode(google_service_account_key.stackgres_sa_key.private_key)
  }
  type = "Opaque"
  depends_on = [kubernetes_namespace.timescale_db_namespace]
}

# 7. Kubernetes Secret for database user
resource "kubernetes_secret" "db_user_secret" {
  metadata {
    name      = "my-db-creds-secret"
    namespace = var.k8s_namespace
  }
  data = {
    "create-db-user-sql" = "create user db_user password '${var.db_password}';"
  }
  type = "Opaque"
  depends_on = [kubernetes_namespace.timescale_db_namespace]
}

# 8. Kubernetes Service Account for StackGres
resource "kubernetes_service_account_v1" "stackgres_k8s_sa" {
  metadata {
    name      = "stackgres-timescaledb-k8s-sa"
    namespace = var.k8s_namespace
    annotations = {
      "iam.gke.io/gcp-service-account" = "stackgres-backup-sa@${var.gcp_project_id}.iam.gserviceaccount.com"
    }
  }
  depends_on = [kubernetes_namespace.timescale_db_namespace]
}
