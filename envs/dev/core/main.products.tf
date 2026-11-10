# Data products, assets, access groups and published definitions (design §3.2, §3.2.1, §3.4,
# §3.8; AT-08, AT-09).

locals {
  # Access groups exist only for published and deprecated products (design §3.8).
  product_access_groups = {
    for id, p in local.products : id => (
      contains(local.lifecycles_with_groups, p.lifecycle) ? {
        for g, v in p.access_groups : g => merge(v, {
          email = "dda-dp-${id}-${var.env}-${g}@${local.group_domain}"
        })
      } : {}
    )
  }

  access_groups = merge([
    for id, groups in local.product_access_groups : {
      for g, v in groups : "${id}/${g}" => merge(v, { product = id, group = g })
    }
  ]...)

  assets = merge([
    for id, p in local.products : {
      for a, v in p.assets : "${id}/${a}" => {
        product  = id
        asset    = a
        dataset  = split(".", v.table)[0]
        table    = split(".", v.table)[1]
        form     = v.form
        access   = { for g, role in v.access : g => role if contains(keys(local.product_access_groups[id]), g) }
        resource = "//bigquery.googleapis.com/projects/${local.analytics_project}/datasets/${split(".", v.table)[0]}/tables/${split(".", v.table)[1]}"
        ref      = v.table
      }
    }
  ]...)

  # Asset resources are immutable and must exist, so assets are declared for tables that exist at
  # plan time (main.inputs.tf, "Tables that exist now").
  assets_ready = { for k, a in local.assets : k => a if contains(local.existing_tables, a.ref) }

  # The product's system @dataplex entry, created by the platform with the product.
  # VERIFY IN BUILD (VA-56): the entry name. Read it from the live product after the first apply
  # and correct this pattern if it differs.
  product_entries = {
    for id, p in local.products : id => "projects/${local.analytics_project_number}/locations/${var.region}/entryGroups/@dataplex/entries/projects/${local.analytics_project_number}/locations/${var.region}/dataProducts/${id}"
  }
}

# Product access groups (design §3.2). Terraform declares the group and never its memberships:
# members are added by console approval (phase 1), the access request gate and the reconciler
# (design §6.15.1), so a member added by approval survives an apply (AT-07).
# Requires tf-<business>-<tier> (tf-deployer) to be able to create dda-dp-* groups (§2.4.6).
resource "google_cloud_identity_group" "access" {
  for_each = var.manage_access_groups ? local.access_groups : {}

  parent       = "customers/${local.estate.customer_id}"
  display_name = "${local.products[each.value.product].display_name} ${each.value.display_name} (${var.env})"
  description  = try(each.value.description, null)

  group_key {
    id = each.value.email
  }

  labels = {
    "cloudidentity.googleapis.com/groups.discussion_forum" = ""
  }

  # No initial owner: the creating pipeline account must not become a member, which would give
  # it read access to the product's data.
  initial_group_config = "EMPTY"
}

resource "google_dataplex_data_product" "this" {
  for_each = local.products

  project         = local.analytics_project
  location        = var.region
  data_product_id = each.key
  display_name    = each.value.display_name
  description     = try(each.value.description, null)

  # A group, not individuals (C2). VERIFY IN BUILD (VA-55): ownerEmails accepts a group and
  # approval notifications reach its members.
  owner_emails = [each.value.owners_group]

  labels = {
    "dda-lifecycle" = each.value.lifecycle
  }

  dynamic "access_approval_config" {
    for_each = length(try(each.value.approvers, [])) > 0 ? [each.value.approvers] : []
    content {
      approver_emails = access_approval_config.value
    }
  }

  dynamic "access_groups" {
    for_each = local.product_access_groups[each.key]
    content {
      id           = access_groups.key
      group_id     = access_groups.key
      display_name = access_groups.value.display_name
      description  = try(access_groups.value.description, null)
      # G8: every access group principal is a Google group.
      principal {
        google_group = access_groups.value.email
      }
    }
  }

  depends_on = [google_cloud_identity_group.access]
}

resource "google_dataplex_data_product_data_asset" "this" {
  for_each = local.assets_ready

  project         = local.analytics_project
  location        = var.region
  data_product_id = google_dataplex_data_product.this[each.value.product].data_product_id
  data_asset_id   = replace(each.value.asset, "_", "-")
  resource        = each.value.resource

  # One IAM role per access group per asset (design §3.2; G6).
  dynamic "access_group_configs" {
    for_each = each.value.access
    content {
      access_group = access_group_configs.key
      iam_roles    = [access_group_configs.value]
    }
  }
}

# Data product IAM (design §6.15.1: google_dataplex_data_product_iam_member, domain core stack).
# The only product grant the design names for a domain stack is ddaDomainDelegate to the analytics
# subdomain's policy_member, which the binding module applies (main.bindings.tf). Owners and
# approvers act through owner_emails and access_approval_config, so no other member is declared.

# Published product definitions for the evaluator's contract writer (design §3.2.1;
# schemas/published_product.schema.json). One writer: this domain's pipeline.
resource "google_storage_bucket_object" "published_product" {
  for_each = local.products

  bucket       = local.hub_state_bucket
  name         = "products/${var.env}/${local.domain}/${each.key}.json"
  content_type = "application/json"
  content = jsonencode(merge(
    {
      env                    = var.env
      domain                 = local.domain
      product_id             = each.key
      product_name           = google_dataplex_data_product.this[each.key].name
      dataplex_entry         = local.product_entries[each.key]
      steward_group          = each.value.steward_group
      owners_group           = each.value.owners_group
      aggregate_dq_threshold = each.value.contract.aggregate_dq_threshold
      lifecycle              = each.value.lifecycle
      assets = {
        for a, v in each.value.assets : a => {
          table_resource = local.assets["${each.key}/${a}"].resource
          form           = v.form
        }
      }
      refresh_cadence = each.value.contract.refresh_cadence
    },
    var.commit_sha == "" ? {} : { commit = var.commit_sha }
  ))
}

# Products created, for the contract stack (design §6.13.3; schemas/outputs_domain.schema.json).
resource "google_storage_bucket_object" "outputs" {
  bucket       = var.tf_state_bucket
  name         = "outputs/dda-${var.business}/${var.env}/outputs.json"
  content_type = "application/json"
  content = jsonencode({
    env    = var.env
    domain = local.domain
    products = {
      for id, p in google_dataplex_data_product.this : id => {
        name           = p.name
        project_id     = local.analytics_project
        location       = var.region
        dataplex_entry = local.product_entries[id]
      }
    }
  })
}
