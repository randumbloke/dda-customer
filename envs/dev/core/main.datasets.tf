# Datasets and their access entries (design §3.3, §6.15.2; AT-04).
#
# Each dataset is created with an explicit minimal access list (the creating pipeline as OWNER,
# the domain's ingest or analytics account as WRITER, the domain owners group as READER) and
# ignore_changes on access. Because the list is explicit, BigQuery adds no projectReaders,
# projectWriters or projectOwners entry (VA-90). Every later grant is a separate
# google_bigquery_dataset_access entry, so runtime grants survive applies (AT-07).
# VERIFY IN BUILD (VA-94): entries added later in the same apply, and at run time, survive
# re-applies; an iam_member entry accepts the custom role ddaDomainDelegate (granted by the
# binding module).
resource "google_bigquery_dataset" "this" {
  for_each = local.datasets

  project     = each.value.project
  dataset_id  = each.key
  location    = var.region
  description = each.value.description

  labels = merge(local.labels_doc.datasets, {
    "dda-stage"        = each.value.stage
    "cdmc-sensitivity" = each.value.sensitivity
  })

  access {
    role          = "OWNER"
    user_by_email = local.pipeline_account
  }
  access {
    role          = "WRITER"
    user_by_email = each.value.writer
  }
  access {
    role           = "READER"
    group_by_email = local.owners_group
  }

  lifecycle {
    ignore_changes = [access]
  }

  depends_on = [terraform_data.declarative_checks]
}

locals {
  # Datasets that hold at least one scanned table (design §2.4.5).
  scanned_datasets = toset([for f, s in local.dq_docs : split(".", s.table)[0]])

  # The analytics account reads the domain's curated datasets to build product tables (§2.4.3).
  curated_datasets = toset([for name, d in local.datasets : name if d.stage == "curated"])
}

# Dataplex service agent of the data project: read on each dataset that holds a scanned table, so
# data quality scans can read it (design §2.4.5). VERIFY IN BUILD (VA-58).
resource "google_bigquery_dataset_access" "dataplex_agent_reader" {
  for_each = local.scanned_datasets

  project       = local.datasets[each.key].project
  dataset_id    = google_bigquery_dataset.this[each.key].dataset_id
  role          = "READER"
  user_by_email = local.dataplex_agents[local.datasets[each.key].project]
}

# The domain's analytics account reads its curated datasets (design §2.4.3).
resource "google_bigquery_dataset_access" "analytics_reader" {
  for_each = local.curated_datasets

  project       = local.datasets[each.key].project
  dataset_id    = google_bigquery_dataset.this[each.key].dataset_id
  role          = "READER"
  user_by_email = local.analytics_account
}
