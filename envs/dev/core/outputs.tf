output "domain" {
  description = "Data domain ID."
  value       = local.domain
}

output "datasets" {
  description = "Datasets created, with project and stage."
  value       = { for k, d in google_bigquery_dataset.this : k => { project = d.project, stage = local.datasets[k].stage } }
}

output "products" {
  description = "Products created and their @dataplex entry names (also in outputs.json)."
  value       = { for id, p in google_dataplex_data_product.this : id => { name = p.name, dataplex_entry = local.product_entries[id] } }
}

output "scans" {
  description = "Data quality scans declared, by scan ID."
  value       = { for id, s in google_dataplex_datascan.dq : id => s.name }
}

output "pending_tables" {
  description = "Declared tables that do not exist yet, so their scans, assets or contacts wait for the next apply."
  value = sort(distinct(concat(
    [for id, sc in local.scan_settings : sc.spec.table if !contains(local.existing_tables, sc.spec.table)],
    [for k, a in local.assets : a.ref if !contains(local.existing_tables, a.ref)],
    [for t, c in local.table_contacts : t if !contains(local.existing_tables, t)],
  )))
}
