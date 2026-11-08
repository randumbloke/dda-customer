# Plan-level tests of the contract stack with mocked providers (terraform test).

# Run with the stack's values: terraform test -var-file=dev.tfvars

mock_provider "google" {}
mock_provider "google-beta" {}

# Every declared product published by core gets its refresh-cadence from the product file.
run "published_products" {
  command = plan

  override_data {
    target = data.google_storage_bucket_object_content.domain_outputs
    values = {
      content = jsonencode({
        env    = "dev"
        domain = "x-dev"
        products = {
          for f in fileset("../../../products", "*.yaml") : trimsuffix(f, ".yaml") => {
            name           = "projects/p/locations/australia-southeast1/dataProducts/${trimsuffix(f, ".yaml")}"
            project_id     = "kcdda-x-analytics-dev"
            location       = "australia-southeast1"
            dataplex_entry = "projects/333/locations/australia-southeast1/entryGroups/@dataplex/entries/projects/333/locations/australia-southeast1/dataProducts/${trimsuffix(f, ".yaml")}"
          }
        }
      })
    }
  }
  override_resource {
    target = google_dataplex_entry.product
    values = {}
  }

  assert {
    condition     = length(google_dataplex_entry.product) == length(fileset("../../../products", "*.yaml"))
    error_message = "one contract per published product"
  }
  assert {
    condition = alltrue([for id, e in google_dataplex_entry.product :
      e.entry_group_id == "@dataplex"
      && e.entry_id == "projects/333/locations/australia-southeast1/dataProducts/${id}"
      && jsondecode(e.aspects[0].aspect[0].data).thresholdInMinutes == yamldecode(file("../../../products/${id}.yaml")).contract.refresh_cadence.threshold_minutes
      && jsondecode(e.aspects[0].aspect[0].data).frequency == yamldecode(file("../../../products/${id}.yaml")).contract.refresh_cadence.frequency
    ])
    error_message = "refresh-cadence comes from contract.refresh_cadence"
  }
}

# A product core has not published yet is not imported.
run "nothing_published" {
  command = plan

  override_data {
    target = data.google_storage_bucket_object_content.domain_outputs
    values = { content = "{\"env\": \"dev\", \"domain\": \"x-dev\", \"products\": {}}" }
  }

  assert {
    condition     = length(google_dataplex_entry.product) == 0
    error_message = "no import before core publishes"
  }
}

# Out-of-order apply: no outputs.json fails the plan (AT-26).
run "missing_outputs_fails_plan" {
  command = plan

  override_data {
    target = data.google_storage_bucket_object_content.domain_outputs
    values = { content = "" }
  }

  expect_failures = [data.google_storage_bucket_object_content.domain_outputs]
}
