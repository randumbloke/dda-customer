# Plan-level tests of the core stack with mocked providers (terraform test). They evaluate the
# generic HCL against this repository's declarative files: no cloud calls.
#
# Every published file is mocked with one merged document that holds the keys of all five files
# (estate, platform tier and env, governance tier and env), shaped as the contract schemas.

# Run with the stack's values: terraform test -var-file=dev.tfvars

mock_provider "google" {
  override_data {
    target = data.google_storage_bucket_object_content.published
    values = {
      content = <<-JSON
        {
          "organization_id": "1059663003036", "customer_id": "C00000000", "group_domain": "mikegyoung.joonix.net",
          "single_deployer": true, "cicd_project_id": "pltfrm-ngnrng",
          "deployer_service_accounts": {"apply": "tf-deployer@pltfrm-ngnrng.iam.gserviceaccount.com", "plan": "tf-deployer-plan@pltfrm-ngnrng.iam.gserviceaccount.com"},
          "tier": "nonprod", "hub_project_id": "kcdda-dgov-hub-nonprod", "hub_project_number": "111",
          "hub_state_bucket": "kcdda-dgov-hub-nonprod-dda-state",
          "env": "dev",
          "projects": {
            "core": {"project_id": "kcdda-core-dwh-dev", "number": "222", "service_agents": {"dataplex": "service-222@gcp-sa-dataplex.iam.gserviceaccount.com"}},
            "customer": {"project_id": "kcdda-customer-analytics-dev", "number": "333", "service_agents": {"dataplex": "service-333@gcp-sa-dataplex.iam.gserviceaccount.com"}},
            "accounts": {"project_id": "kcdda-accounts-analytics-dev", "number": "444", "service_agents": {"dataplex": "service-444@gcp-sa-dataplex.iam.gserviceaccount.com"}}
          },
          "landing_buckets": {"customer": "kcdda-core-dwh-dev-customer-landing", "accounts": "kcdda-core-dwh-dev-accounts-landing"},
          "domain_service_accounts": {
            "customer": {"ingest": "customer-ingest-dev@kcdda-core-dwh-dev.iam.gserviceaccount.com", "analytics": "customer-analytics-dev@kcdda-customer-analytics-dev.iam.gserviceaccount.com"},
            "accounts": {"ingest": "accounts-ingest-dev@kcdda-core-dwh-dev.iam.gserviceaccount.com", "analytics": "accounts-analytics-dev@kcdda-accounts-analytics-dev.iam.gserviceaccount.com"}
          },
          "domains": {
            "customer-dev": {"name": "projects/kcdda-dgov-hub-nonprod/locations/australia-southeast1/dataDomains/customer-dev", "policy_member": "principal://dataplex.googleapis.com/customer-dev",
              "subdomains": {
                "raw": {"name": "projects/kcdda-dgov-hub-nonprod/locations/australia-southeast1/dataDomains/customer-dev-raw", "policy_member": "principal://x/customer-dev-raw"},
                "staging": {"name": "projects/kcdda-dgov-hub-nonprod/locations/australia-southeast1/dataDomains/customer-dev-staging", "policy_member": "principal://x/customer-dev-staging"},
                "curated": {"name": "projects/kcdda-dgov-hub-nonprod/locations/australia-southeast1/dataDomains/customer-dev-curated", "policy_member": "principal://x/customer-dev-curated"},
                "analytics": {"name": "projects/kcdda-dgov-hub-nonprod/locations/australia-southeast1/dataDomains/customer-dev-analytics", "policy_member": "principal://x/customer-dev-analytics"}}},
            "accounts-dev": {"name": "projects/kcdda-dgov-hub-nonprod/locations/australia-southeast1/dataDomains/accounts-dev", "policy_member": "principal://dataplex.googleapis.com/accounts-dev",
              "subdomains": {
                "raw": {"name": "projects/kcdda-dgov-hub-nonprod/locations/australia-southeast1/dataDomains/accounts-dev-raw", "policy_member": "principal://x/accounts-dev-raw"},
                "staging": {"name": "projects/kcdda-dgov-hub-nonprod/locations/australia-southeast1/dataDomains/accounts-dev-staging", "policy_member": "principal://x/accounts-dev-staging"},
                "curated": {"name": "projects/kcdda-dgov-hub-nonprod/locations/australia-southeast1/dataDomains/accounts-dev-curated", "policy_member": "principal://x/accounts-dev-curated"},
                "analytics": {"name": "projects/kcdda-dgov-hub-nonprod/locations/australia-southeast1/dataDomains/accounts-dev-analytics", "policy_member": "principal://x/accounts-dev-analytics"}}}
          },
          "hub_datasets": {"australia-southeast1": {"dq_results": "dq_results", "cdmc_findings": "cdmc_findings"}},
          "cdmc_report_dataset": "cdmc_report", "discovery_configs": {}, "service_urls": {},
          "products": {}
        }
      JSON
    }
  }

  mock_data "google_bigquery_datasets" {
    defaults = { datasets = [] }
  }
  mock_data "google_bigquery_tables" {
    defaults = { tables = [] }
  }
  mock_data "google_project" {
    defaults = { number = "999", org_id = "1059663003036" }
  }
}

mock_provider "google-beta" {}

# First apply: nothing exists yet, so datasets, bindings and products are planned, and scans,
# assets and table contacts wait for the tables.
run "first_apply" {
  command = plan

  assert {
    condition     = length(google_bigquery_dataset.this) == length(yamldecode(file("../../../datasets.yaml")).datasets)
    error_message = "one dataset per datasets.yaml entry"
  }
  assert {
    condition = alltrue([for k, d in google_bigquery_dataset.this :
      d.labels["dda-domain"] == "${var.business}-dev" && d.labels["dda-stage"] == split("_", k)[1] && contains(["sensitive", "non-sensitive"], d.labels["cdmc-sensitivity"])
    ])
    error_message = "dataset labels (AT-04)"
  }
  assert {
    condition = alltrue([for k, d in google_bigquery_dataset.this :
      length(d.access) == 3 && !anytrue([for a in d.access : try(a.special_group, null) != null])
    ])
    error_message = "minimal access list with no special groups (AT-04)"
  }
  assert {
    condition     = length(local.binding_sets) == length(distinct([for d in local.datasets : d.stage]))
    error_message = "one binding module call per declared stage"
  }
  assert {
    condition = alltrue(flatten([for stage, set in local.binding_sets : [
      for k, r in set : can(regex("^(ds|dp)-[a-z0-9-]+$", k))
    ]]))
    error_message = "binding keys follow ds-/dp- (contracts §2)"
  }
  assert {
    condition     = length(google_dataplex_data_product.this) == length(fileset("../../../products", "*.yaml"))
    error_message = "one product per products/*.yaml"
  }
  assert {
    condition     = length(google_dataplex_datascan.dq) == 0 && length(google_dataplex_data_product_data_asset.this) == 0 && length(google_dataplex_entry.table_contacts) == 0
    error_message = "scans, assets and contacts wait for tables"
  }
  assert {
    condition     = google_storage_bucket_object.outputs.name == "outputs/dda-${var.business}/dev/outputs.json"
    error_message = "outputs.json path"
  }
  assert {
    condition     = google_storage_bucket_object.bindings.name == "bindings/dev/${var.business}-dev/bindings.json"
    error_message = "bindings.json path"
  }
  assert {
    condition     = google_storage_bucket_object.lineage_manifest.name == "lineage/dev/${var.business}-dev/manifest.json"
    error_message = "lineage manifest path"
  }
  assert {
    condition     = length(google_cloud_run_v2_job.pipeline) == 0
    error_message = "pipeline jobs are off by default"
  }
}

# After the pipeline has created every declared table.
run "tables_exist" {
  command = plan

  # The table entries are adopted with import blocks, which mock providers cannot serve.
  override_resource {
    target = google_dataplex_entry.table_contacts
    values = {}
  }

  override_data {
    target = data.google_bigquery_datasets.existing
    values = {
      datasets = [for name in keys(yamldecode(file("../../../datasets.yaml")).datasets) : { dataset_id = name, friendly_name = "", labels = {}, location = "australia-southeast1" }]
    }
  }
  override_data {
    target = data.google_bigquery_tables.existing
    values = {
      tables = [for t in distinct(concat(
        [for f in fileset("../../../dq", "*/*.yaml") : split(".", yamldecode(file("../../../dq/${f}")).table)[1]],
        flatten([for f in fileset("../../../products", "*.yaml") : [for a in values(yamldecode(file("../../../products/${f}")).assets) : split(".", a.table)[1]]]),
        [for t in keys(try(yamldecode(file("../../../datasets.yaml")).table_contacts, {})) : split(".", t)[1]],
      )) : { table_id = t, labels = {} }]
    }
  }

  assert {
    condition     = length(google_dataplex_datascan.dq) == length(fileset("../../../dq", "*/*.yaml"))
    error_message = "one scan per dq/ specification"
  }
  assert {
    condition = alltrue([for id, s in google_dataplex_datascan.dq :
      length(id) <= 63 && startswith(id, "dq-") && s.data_quality_spec[0].catalog_publishing_enabled == true
      && s.data_quality_spec[0].post_scan_actions[0].bigquery_export[0].results_table == "//bigquery.googleapis.com/projects/kcdda-dgov-hub-nonprod/datasets/dq_results/tables/scan_results"
      && s.labels["dda-env"] == "dev"
    ])
    error_message = "scan ID, publishing, export and labels (§3.6)"
  }
  assert {
    condition = alltrue(flatten([for id, s in google_dataplex_datascan.dq : [
      for r in s.data_quality_spec[0].rules : r.threshold == null || (r.threshold >= 0 && r.threshold <= 1)
    ]]))
    error_message = "rule thresholds are ratios"
  }
  assert {
    condition     = length(google_dataplex_data_product_data_asset.this) == sum([for f in fileset("../../../products", "*.yaml") : length(yamldecode(file("../../../products/${f}")).assets)])
    error_message = "one asset per declared asset"
  }
  assert {
    condition     = length(google_dataplex_entry.table_contacts) == length(try(yamldecode(file("../../../datasets.yaml")).table_contacts, {}))
    error_message = "table contacts for every declared table"
  }
}

# A missing published file fails the plan (AT-26).
run "missing_published_file_fails_plan" {
  command = plan

  override_data {
    target = data.google_storage_bucket_object_content.published
    values = { content = "" }
  }

  expect_failures = [data.google_storage_bucket_object_content.published]
}

# Scan ID shortening rule (contracts §2).
run "scan_id_rule" {
  command = plan

  assert {
    condition = alltrue([for f, s in local.dq_docs :
      contains(keys(local.scans), "dq-${replace(replace(s.table, ".", "-"), "_", "-")}") || length("dq-${replace(replace(s.table, ".", "-"), "_", "-")}") > 63
    ])
    error_message = "scan IDs are dq-<dataset>-<table>"
  }
}

# Pipeline jobs and schedules when the flag is on (P6-39).
run "pipeline_enabled" {
  command = plan

  variables {
    pipeline = {
      enabled  = true
      image    = "australia-southeast1-docker.pkg.dev/pltfrm-ngnrng/dda-pipelines/x:1"
      schedule = "0 5 * * *"
      timezone = "Australia/Sydney"
    }
  }

  # Consumed product definitions (dda-accounts reads Customer Profile's).
  override_data {
    target = data.google_storage_bucket_object_content.consumed_product
    values = {
      content = "{\"assets\": {\"customer_profile\": {\"table_resource\": \"//bigquery.googleapis.com/projects/kcdda-customer-analytics-dev/datasets/customer_analytics/tables/customer_profile\", \"form\": \"pipeline_table\"}}}"
    }
  }

  assert {
    condition     = google_cloud_run_v2_job.pipeline["ingest"].template[0].template[0].service_account == "${var.business}-ingest-dev@kcdda-core-dwh-dev.iam.gserviceaccount.com"
    error_message = "ingest job runs as the ingest account"
  }
  assert {
    condition     = google_cloud_run_v2_job.pipeline["build"].project == "kcdda-${var.business}-analytics-dev"
    error_message = "build job runs in the analytics project"
  }
  assert {
    condition     = google_cloud_scheduler_job.pipeline["ingest"].schedule == "0 5 * * *" && google_cloud_scheduler_job.pipeline["build"].schedule == "0 6 * * *"
    error_message = "build runs one hour after ingest"
  }
  assert {
    condition     = alltrue([for k, v in local.consumed_tables : v == "kcdda-customer-analytics-dev.customer_analytics.customer_profile"])
    error_message = "consumed tables resolve to project.dataset.table"
  }
}

# Mocked apply: the published files carry every key their contract schema requires.
run "published_files_match_contracts" {
  command = apply

  # The binding module calls the Data Domains API from local-exec; never run it in tests.
  override_module {
    target  = module.binding
    outputs = { binding_names = {} }
  }

  assert {
    condition = alltrue([for id, o in google_storage_bucket_object.published_product :
      length(setsubtract(jsondecode(file("../../../schemas/published_product.schema.json")).required, keys(jsondecode(o.content)))) == 0
      && length(setsubtract(keys(jsondecode(o.content)), keys(jsondecode(file("../../../schemas/published_product.schema.json")).properties))) == 0
    ])
    error_message = "published product definitions match published_product.schema.json keys"
  }
  assert {
    condition = alltrue([for id, o in google_storage_bucket_object.published_product :
      o.name == "products/dev/${var.business}-dev/${id}.json" && jsondecode(o.content).domain == "${var.business}-dev"
    ])
    error_message = "published product path and domain"
  }
  assert {
    condition     = length(setsubtract(jsondecode(file("../../../schemas/outputs_domain.schema.json")).required, keys(jsondecode(google_storage_bucket_object.outputs.content)))) == 0
    error_message = "outputs.json matches outputs_domain.schema.json keys"
  }
  assert {
    condition = alltrue([for id, p in jsondecode(google_storage_bucket_object.outputs.content).products :
      length(setsubtract(["name", "project_id", "location", "dataplex_entry"], keys(p))) == 0
    ])
    error_message = "outputs.json products carry name, project_id, location, dataplex_entry"
  }
  assert {
    condition = alltrue([for k, b in jsondecode(google_storage_bucket_object.bindings.content).bindings :
      can(regex("^(ds|dp)-[a-z0-9-]+$", k)) && startswith(b.resource, "//") && b.domain_name != ""
    ])
    error_message = "bindings.json matches bindings.schema.json"
  }
  assert {
    condition     = length(jsondecode(google_storage_bucket_object.bindings.content).bindings) == length(local.datasets) + length(local.products)
    error_message = "one binding per dataset and product (AT-05)"
  }
}
