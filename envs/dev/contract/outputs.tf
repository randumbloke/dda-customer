output "contracts" {
  description = "Products whose refresh-cadence aspect this stack manages, with their entry names."
  value       = { for id, c in local.contracts : id => c.entry_name }
}
