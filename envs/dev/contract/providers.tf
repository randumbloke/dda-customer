terraform {
  required_version = ">= 1.17"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.10"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 8.10"
    }
  }
}

provider "google" {
  region                = var.region
  user_project_override = var.billing_project != null && var.billing_project != ""
  billing_project       = var.billing_project != "" ? var.billing_project : null
}

provider "google-beta" {
  region                = var.region
  user_project_override = var.billing_project != null && var.billing_project != ""
  billing_project       = var.billing_project != "" ? var.billing_project : null
}
