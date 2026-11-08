# State bucket and prefix come from state.config (terraform init -backend-config=state.config).
terraform {
  backend "gcs" {}
}
