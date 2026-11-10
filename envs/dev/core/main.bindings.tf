# Domain bindings (design §2.3, §2.3.1, §3.3; AT-05).
#
# Each dataset is bound to the subdomain for its stage, and each product to the analytics
# subdomain, through the binding submodule of dda-platform. The module grants the subdomain's
# policy_member the organisation custom role ddaDomainDelegate on each resource before it creates
# the binding (design §2.3.2 table), so this stack declares no delegate grant itself.
# Binding keys: ds-<dataset with _ as -> and dp-<product-id> (contracts README §2).
# VERIFY IN BUILD (VA-12): policy_member can be granted like any other principal.
# VERIFY IN BUILD (VA-49): ddaDomainDelegate is sufficient to create a binding.
# VERIFY IN BUILD (VA-87): ddaDomainBinder on the domain authorises bindings to its subdomains.

locals {
  stages = toset([for d in local.datasets : d.stage])

  # IAM full resource names. Built from known strings, with a reference to the resource for
  # ordering, so the map is known at plan time.
  dataset_resources = {
    for name, d in local.datasets : name => "//bigquery.googleapis.com/projects/${d.project}/datasets/${google_bigquery_dataset.this[name].dataset_id}"
  }
  # The bindings API accepts a product only by project number (VA-15, OD-9); datasets use the ID.
  product_resources = {
    for id, p in local.products : id => "//dataplex.googleapis.com/projects/${local.analytics_project_number}/locations/${var.region}/dataProducts/${google_dataplex_data_product.this[id].data_product_id}"
  }

  binding_sets = {
    for stage in local.stages : stage => merge(
      { for name, d in local.datasets : "ds-${replace(name, "_", "-")}" => local.dataset_resources[name] if d.stage == stage },
      stage == "analytics" ? { for id, p in local.products : "dp-${id}" => local.product_resources[id] } : {}
    )
  }
}

module "binding" {
  source   = "git::https://github.com/randumbloke/dda-platform.git//modules/data_domain_shim/binding?ref=main"
  for_each = local.binding_sets

  domain_name   = local.domain_state.subdomains[each.key].name
  policy_member = local.domain_state.subdomains[each.key].policy_member
  bindings      = each.value
}

# Declared bindings for the reconciler (design §2.3.2; schemas/bindings.schema.json), written in
# the same apply. One writer: this domain's pipeline (managed folder bindings/<env>/<domain>/).
resource "google_storage_bucket_object" "bindings" {
  bucket       = local.hub_state_bucket
  name         = "bindings/${var.env}/${local.domain}/bindings.json"
  content_type = "application/json"
  content = jsonencode({
    env    = var.env
    domain = local.domain
    bindings = merge([
      for stage, set in local.binding_sets : {
        for key, resource in set : key => {
          domain_name = local.domain_state.subdomains[stage].name
          resource    = resource
        }
      }
    ]...)
  })

  depends_on = [module.binding]
}
