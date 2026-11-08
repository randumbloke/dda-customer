# Table contacts (design §3.3; C2). The pipeline is the only writer of the contacts aspect on a
# table entry (ddaMetadataSteward has no useContactsAspect, §1.5.2). The table's @bigquery entry
# is created by the platform when the pipeline creates the table, so Terraform adopts it with an
# import block, for tables that exist at plan time (main.inputs.tf).
# VERIFY IN BUILD (VA-42): writing the contacts system aspect with entries.update and
# entryGroups.useContactsAspect (ddaPipelineCatalogWriter).
# VERIFY IN BUILD (VA-56): google_dataplex_entry on a system entry changes only the aspects it
# declares; if not, write the aspect with entries.patch and an aspectKeys mask instead.

locals {
  table_contacts = {
    for t, c in try(local.datasets_doc.table_contacts, {}) : t => {
      dataset  = split(".", t)[0]
      table    = split(".", t)[1]
      project  = local.datasets[split(".", t)[0]].project
      owner    = try(c.owner, null)
      steward  = try(c.steward, null)
      entry_id = "bigquery.googleapis.com/projects/${local.datasets[split(".", t)[0]].project}/datasets/${split(".", t)[0]}/tables/${split(".", t)[1]}"
    }
  }
  table_contacts_ready = { for t, c in local.table_contacts : t => c if contains(local.existing_tables, t) }
}

import {
  for_each = local.table_contacts_ready
  to       = google_dataplex_entry.table_contacts[each.key]
  id       = "projects/${each.value.project}/locations/${var.region}/entryGroups/@bigquery/entries/${each.value.entry_id}"
}

resource "google_dataplex_entry" "table_contacts" {
  for_each = local.table_contacts_ready

  project        = each.value.project
  location       = var.region
  entry_group_id = "@bigquery"
  entry_id       = each.value.entry_id
  entry_type     = "projects/655216118709/locations/global/entryTypes/bigquery-table" # dataplex-types project number; ignored after import (VA-56)

  aspects {
    aspect_key = "dataplex-types.global.contacts"
    aspect {
      data = jsonencode({
        identities = concat(
          each.value.owner == null ? [] : [{ role = "Owner", name = each.value.owner, id = each.value.owner }],
          each.value.steward == null ? [] : [{ role = "Steward", name = each.value.steward, id = each.value.steward }],
        )
      })
    }
  }

  # The platform owns the system entry: never delete it, and ignore what the platform sets.
  deletion_policy = "ABANDON"

  lifecycle {
    ignore_changes = [entry_type, entry_source, fully_qualified_name, parent_entry]
  }
}
