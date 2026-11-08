# Inputs: published values from other repositories (design §6.13.3) and this repository's
# declarative files (design §3). Nothing here is repeated in .tfvars.

# ---------------------------------------------------------------------------------------------
# Published files in the Terraform state bucket. A missing file fails the plan, so a stack
# applied out of order changes nothing (AT-26). No terraform_remote_state.
# ---------------------------------------------------------------------------------------------
locals {
  published_paths = {
    estate          = "bootstrap/estate.json"
    platform_tier   = "outputs/dda-platform/tiers/${var.tier}/outputs.json"
    platform_env    = "outputs/dda-platform/${var.env}/outputs.json"
    governance_tier = "outputs/cdmc-governance/tiers/${var.tier}/outputs.json"
    governance_env  = "outputs/cdmc-governance/${var.env}/outputs.json"
  }
}

data "google_storage_bucket_object_content" "published" {
  for_each = local.published_paths
  bucket   = var.tf_state_bucket
  name     = each.value

  lifecycle {
    postcondition {
      condition     = self.content != null && trimspace(coalesce(self.content, "")) != ""
      error_message = "Published file gs://${var.tf_state_bucket}/${each.value} is missing or empty: apply the stack that writes it first (design §6.14, AT-26)."
    }
  }
}

locals {
  estate          = jsondecode(data.google_storage_bucket_object_content.published["estate"].content)
  platform_tier   = jsondecode(data.google_storage_bucket_object_content.published["platform_tier"].content)
  platform_env    = jsondecode(data.google_storage_bucket_object_content.published["platform_env"].content)
  governance_tier = jsondecode(data.google_storage_bucket_object_content.published["governance_tier"].content)
  governance_env  = jsondecode(data.google_storage_bucket_object_content.published["governance_env"].content)

  domain       = "${var.business}-${var.env}" # data domain ID, for example customer-dev
  group_domain = local.estate.group_domain

  hub_project_id   = local.platform_tier.hub_project_id
  hub_state_bucket = local.governance_tier.hub_state_bucket
  core_project     = local.platform_env.projects["core"].project_id
  # In the 3-project layout both domains share one analytics project; the platform outputs still
  # key it by business (outputs_platform_env.schema.json).
  analytics_project        = local.platform_env.projects[var.business].project_id
  analytics_project_number = local.platform_env.projects[var.business].number

  # Dataplex service agents by project ID. VERIFY IN BUILD (VA-58): the key name "dataplex" in
  # service_agents is not fixed by the contract schema; agreed with the dda-platform draft.
  dataplex_agents = {
    (local.core_project)      = local.platform_env.projects["core"].service_agents["dataplex"]
    (local.analytics_project) = local.platform_env.projects[var.business].service_agents["dataplex"]
  }

  ingest_account    = local.platform_env.domain_service_accounts[var.business].ingest
  analytics_account = local.platform_env.domain_service_accounts[var.business].analytics
  landing_bucket    = local.platform_env.landing_buckets[var.business]

  # The pipeline account that creates the datasets (dataset OWNER, design §6.15.2). With
  # single_deployer every trigger applies as tf-deployer (design §6.7.2).
  pipeline_account = local.estate.single_deployer ? local.estate.deployer_service_accounts.apply : "tf-${var.business}-${var.tier}@${coalesce(local.estate.cicd_project_id, local.hub_project_id)}.iam.gserviceaccount.com"

  domain_state       = local.governance_env.domains[local.domain]
  dq_results_dataset = local.governance_env.hub_datasets[var.region].dq_results
  dq_results_table   = "//bigquery.googleapis.com/projects/${local.hub_project_id}/datasets/${local.dq_results_dataset}/tables/scan_results"

  owners_group = "dda-${var.business}-${var.env}-owners@${local.group_domain}"

  labels_doc = jsondecode(replace(replace(file("${local.root}/envs/labels.json"), "{business}", var.business), "{env}", var.env))
}

# ---------------------------------------------------------------------------------------------
# Declarative files (design §3.1). {env} is replaced before use. The .tf files are generic, so
# every domain repository uses them unchanged.
# ---------------------------------------------------------------------------------------------
locals {
  root = "${path.module}/${var.repo_root}"

  datasets_doc = yamldecode(replace(file("${local.root}/datasets.yaml"), "{env}", var.env))

  datasets = {
    for name, d in local.datasets_doc.datasets : name => {
      stage       = d.stage
      sensitivity = d.sensitivity
      description = try(d.description, null)
      project     = d.stage == "analytics" ? local.analytics_project : local.core_project
      writer      = d.stage == "analytics" ? local.analytics_account : local.ingest_account
    }
  }

  product_files = fileset("${local.root}/products", "*.yaml")
  product_docs = {
    for f in local.product_files : trimsuffix(f, ".yaml") => yamldecode(replace(file("${local.root}/products/${f}"), "{env}", var.env))
  }
  products = { for k, p in local.product_docs : p.id => p }

  dq_files = fileset("${local.root}/dq", "*/*.yaml")
  dq_docs = {
    for f in local.dq_files : f => yamldecode(replace(file("${local.root}/dq/${f}"), "{env}", var.env))
  }

  # Product lifecycle (design §3.8): only published and deprecated products have access groups.
  lifecycles_with_groups = ["published", "deprecated"]
}

# Declarative-file consistency checks that the JSON Schemas cannot express. A failure stops the
# plan before anything changes.
resource "terraform_data" "declarative_checks" {
  input = {
    products = keys(local.products)
    datasets = keys(local.datasets)
    dq       = keys(local.dq_docs)
  }

  lifecycle {
    precondition {
      condition     = alltrue([for f, p in local.product_docs : f == p.id])
      error_message = "Each products/<id>.yaml must declare id: <id>."
    }
    precondition {
      condition     = alltrue([for name, d in local.datasets : startswith(name, "${var.business}_") && endswith(name, "_${d.stage}")])
      error_message = "Dataset names must be <business>_<stage> (design §3.3)."
    }
    precondition {
      condition     = alltrue([for f, s in local.dq_docs : f == "${replace(s.table, ".", "/")}.yaml"])
      error_message = "Each dq/<dataset>/<table>.yaml must declare table: <dataset>.<table>."
    }
    precondition {
      condition     = alltrue([for f, s in local.dq_docs : contains(keys(local.datasets), split(".", s.table)[0])])
      error_message = "Every scan specification must name a table in a dataset declared in datasets.yaml."
    }
    precondition {
      condition = alltrue(flatten([for id, p in local.products : [
        for a, v in p.assets : contains(keys(local.datasets), split(".", v.table)[0]) && local.datasets[split(".", v.table)[0]].stage == "analytics"
      ]]))
      error_message = "Every asset must be a table in an analytics dataset of this domain (design §3.4, G1)."
    }
    precondition {
      condition     = alltrue([for id, p in local.products : !contains(keys(p.access_groups), "owners")])
      error_message = "No access group ID may be 'owners' (design §3.9, G7)."
    }
    precondition {
      condition = alltrue(flatten([for id, p in local.products : [
        for a, v in p.assets : alltrue([for g in keys(v.access) : contains(keys(p.access_groups), g)])
      ]]))
      error_message = "Every asset access entry must name an access group declared by its product."
    }
    precondition {
      condition     = alltrue([for t in keys(try(local.datasets_doc.table_contacts, {})) : contains(keys(local.datasets), split(".", t)[0])])
      error_message = "table_contacts must name tables in datasets declared in datasets.yaml."
    }
    precondition {
      condition     = alltrue([for id, p in local.products : length(try(p.approvers, [])) <= 10])
      error_message = "At most 10 approvers per product (design §3.2, G5)."
    }
  }
}

# ---------------------------------------------------------------------------------------------
# Tables that exist now. Pipelines, not Terraform, create tables (P6-39), and a table's catalog
# entry exists only after the table. Resources that need an existing table (product assets, table
# contacts, scans) are declared for tables that exist at plan time, so the first apply creates
# datasets and products, the pipeline run creates the tables, and the next apply adds the rest
# (README, "Apply order").
# ---------------------------------------------------------------------------------------------
data "google_bigquery_datasets" "existing" {
  for_each = toset(distinct([for d in local.datasets : d.project]))
  project  = each.key
}

locals {
  existing_dataset_keys = toset(flatten([
    for p, d in data.google_bigquery_datasets.existing : [for ds in d.datasets : "${p}/${ds.dataset_id}"]
  ]))
  existing_declared_datasets = {
    for name, d in local.datasets : name => d if contains(local.existing_dataset_keys, "${d.project}/${name}")
  }
}

data "google_bigquery_tables" "existing" {
  for_each   = local.existing_declared_datasets
  project    = each.value.project
  dataset_id = each.key
}

locals {
  # "<dataset>.<table>" for every table that exists in a declared dataset.
  existing_tables = toset(flatten([
    for ds, t in data.google_bigquery_tables.existing : [for x in t.tables : "${ds}.${x.table_id}"]
  ]))
}
