# Design-time lineage manifest (design §5.4.1, P6-39; schemas/lineage_manifest.schema.json),
# published as is on every deployment. One writer: this domain's pipeline.

locals {
  lineage_manifest_path = "${local.root}/pipelines/lineage/manifest.json"
  lineage_manifest      = jsondecode(file(local.lineage_manifest_path))
}

resource "google_storage_bucket_object" "lineage_manifest" {
  bucket       = local.hub_state_bucket
  name         = "lineage/${var.env}/${local.domain}/manifest.json"
  content_type = "application/json"
  content      = file(local.lineage_manifest_path)

  lifecycle {
    precondition {
      condition     = local.lineage_manifest.domain == local.domain
      error_message = "pipelines/lineage/manifest.json declares domain ${local.lineage_manifest.domain}, not ${local.domain}."
    }
  }
}
