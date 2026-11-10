# Product contracts: the refresh-cadence system aspect on each published product's @dataplex
# entry (design §3.2.1, §3.5; decision P6-21; AT-09).
#
# The platform creates a product's @dataplex entry with the product, so it cannot be imported in
# the apply that creates the product (E2E-48). The core stack publishes the products it created
# in outputs/dda-<business>/<env>/outputs.json; this stack, applied next in the same build, adopts
# each published entry with an import block and sets refresh-cadence. A pull request that adds a
# product does not show it here until core has published it, so the plan never imports an entry
# that does not exist. Terraform is the only writer of refresh-cadence; the contract aspect
# (cdmc-data-product-contract) is written by the evaluator's contract writer only.
#
# VERIFY IN BUILD (VA-56): the entry name, and that google_dataplex_entry on the product's system
# entry changes only the aspects it declares (leaving data-product, contacts and
# cdmc-data-product-contract intact). If it does not, remove google_dataplex_entry.product and
# write refresh-cadence with entries.patch and updateMask/aspectKeys =
# ["dataplex-types.global.refresh-cadence"] in the pipeline instead (design §3.2.1 fallback).

data "google_storage_bucket_object_content" "domain_outputs" {
  bucket = var.tf_state_bucket
  name   = "outputs/dda-${var.business}/${var.env}/outputs.json"

  lifecycle {
    postcondition {
      condition     = trimspace(self.content == null ? "" : self.content) != ""
      error_message = "outputs/dda-${var.business}/${var.env}/outputs.json is missing: apply the core stack first (design §6.13.3, AT-26)."
    }
  }
}

locals {
  root    = "${path.module}/${var.repo_root}"
  outputs = jsondecode(data.google_storage_bucket_object_content.domain_outputs.content)

  product_docs = {
    for f in fileset("${local.root}/products", "*.yaml") :
    trimsuffix(f, ".yaml") => yamldecode(replace(file("${local.root}/products/${f}"), "{env}", var.env))
  }

  # Products that core has published and that are still declared.
  contracts = {
    for id, p in local.outputs.products : id => {
      entry_name = p.dataplex_entry
      project    = regex("^projects/([^/]+)/", p.dataplex_entry)[0]
      location   = p.location
      # projects/<p>/locations/<l>/entryGroups/@dataplex/entries/<entry_id>
      entry_id = regex("^projects/[^/]+/locations/[^/]+/entryGroups/[^/]+/entries/(.+)$", p.dataplex_entry)[0]
      cadence  = local.product_docs[id].contract.refresh_cadence
    } if contains(keys(local.product_docs), id)
  }
}

import {
  for_each = local.contracts
  to       = google_dataplex_entry.product[each.key]
  id       = each.value.entry_name
}

resource "google_dataplex_entry" "product" {
  for_each = local.contracts

  project        = each.value.project
  location       = each.value.location
  entry_group_id = "@dataplex"
  entry_id       = each.value.entry_id
  # VERIFY IN BUILD (VA-56): system entry type of a data product entry. Ignored after import.
  # 655216118709 is the project number of dataplex-types (the provider refuses project IDs).
  entry_type = "projects/655216118709/locations/global/entryTypes/data-product"

  aspects {
    # The provider requires the project-number form of dataplex-types.global.refresh-cadence.
    aspect_key = "655216118709.global.refresh-cadence"
    aspect {
      data = jsonencode(merge(
        {
          frequency          = each.value.cadence.frequency
          thresholdInMinutes = each.value.cadence.threshold_minutes
        },
        try({ refreshTime = each.value.cadence.refresh_time }, {}),
        try({ cronSchedule = each.value.cadence.cron_schedule }, {}),
      ))
    }
  }

  # The platform owns the system entry: never delete it (removing a product from this stack only
  # stops managing its cadence), and ignore what the platform sets.
  deletion_policy = "ABANDON"

  lifecycle {
    ignore_changes = [entry_type, entry_source, fully_qualified_name, parent_entry]
  }
}
