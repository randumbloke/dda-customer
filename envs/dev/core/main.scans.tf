# Data quality scans (design §3.6; C12; AT-14 to AT-17). One google_dataplex_datascan per
# dq/<dataset>/<table>.yaml, in the table's project and region.

locals {
  # Templates whose rules are row-level: a missing threshold defaults to 1.0 (design §3.6).
  # Aggregate templates take no threshold.
  row_level_templates = ["non_null_expectation", "range_expectation", "regex_expectation", "set_expectation", "row_condition_expectation"]

  domain_min_dq_threshold = length(local.products) == 0 ? null : min([for p in local.products : p.contract.aggregate_dq_threshold]...)

  scans = {
    for f, s in local.dq_docs : (
      length("dq-${replace(replace(s.table, ".", "-"), "_", "-")}") > 63
      ? "${substr("dq-${replace(replace(s.table, ".", "-"), "_", "-")}", 0, 54)}-${substr(sha256("dq-${replace(replace(s.table, ".", "-"), "_", "-")}"), 0, 8)}"
      : "dq-${replace(replace(s.table, ".", "-"), "_", "-")}"
      ) => {
      spec    = s
      dataset = split(".", s.table)[0]
      table   = split(".", s.table)[1]
      project = local.datasets[split(".", s.table)[0]].project
      runner  = local.datasets[split(".", s.table)[0]].writer
      stage   = local.datasets[split(".", s.table)[0]].stage
      # Products whose assets include this table (design §3.6 notification_report).
      serving = [for id, p in local.products : id if contains([for a in values(p.assets) : a.table], s.table)]
    }
  }

  scan_settings = {
    for id, sc in local.scans : id => merge(sc, {
      # Owners group of each product the table serves, or the domain owners group if none.
      recipients = length(sc.serving) > 0 ? distinct([for p in sc.serving : local.products[p].owners_group]) : [local.owners_group]
      # Lowest aggregate_dq_threshold of the serving products, both on the 0 to 100 scale (VA-80).
      # A table that serves no product directly uses the domain's lowest product threshold, so a
      # low score on an upstream table still notifies its owners (AT-17).
      score_threshold = length(sc.serving) > 0 ? min([for p in sc.serving : local.products[p].contract.aggregate_dq_threshold]...) : local.domain_min_dq_threshold
    })
  }

  # Scans are declared for tables that exist at plan time (main.inputs.tf, "Tables that exist now").
  scans_ready = { for id, sc in local.scan_settings : id => sc if contains(local.existing_tables, sc.spec.table) }
}

resource "google_dataplex_datascan" "dq" {
  for_each = local.scans_ready

  project      = each.value.project
  location     = var.region
  data_scan_id = each.key
  display_name = "DQ ${each.value.spec.table}"
  description  = "Data quality scan for ${each.value.spec.table}, from dq/${each.value.dataset}/${each.value.table}.yaml."
  labels       = local.labels_doc.scans # dda-domain, dda-env (VA-51)

  data {
    resource = "//bigquery.googleapis.com/projects/${each.value.project}/datasets/${each.value.dataset}/tables/${each.value.table}"
  }

  execution_spec {
    field = try(each.value.spec.incremental_field, null)
    trigger {
      dynamic "on_demand" {
        for_each = each.value.spec.trigger == "on_demand" ? [1] : []
        content {}
      }
      dynamic "schedule" {
        for_each = each.value.spec.trigger == "on_demand" ? [] : [each.value.spec.trigger.schedule]
        content {
          cron = schedule.value
        }
      }
    }
  }

  data_quality_spec {
    # sampling_percent is not set: sensitive tables are scanned in full (design §3.6).
    catalog_publishing_enabled = true # the C12 coverage check fails without it

    dynamic "rules" {
      for_each = each.value.spec.rules
      content {
        name      = rules.value.name
        dimension = rules.value.dimension
        column    = try(rules.value.column, null)
        threshold = contains(local.row_level_templates, rules.value.template) ? try(rules.value.threshold, 1.0) : null
        # VERIFY IN BUILD (VA-34): the attribute survives to the scan result and the export.
        attributes = try(rules.value.critical, false) ? { "cdmc-critical" = "true" } : null

        dynamic "non_null_expectation" {
          for_each = rules.value.template == "non_null_expectation" ? [1] : []
          content {}
        }
        dynamic "uniqueness_expectation" {
          for_each = rules.value.template == "uniqueness_expectation" ? [1] : []
          content {}
        }
        dynamic "range_expectation" {
          for_each = rules.value.template == "range_expectation" ? [try(rules.value.params, {})] : []
          content {
            min_value          = try(tostring(range_expectation.value.min_value), null)
            max_value          = try(tostring(range_expectation.value.max_value), null)
            strict_min_enabled = try(range_expectation.value.strict_min_enabled, null)
            strict_max_enabled = try(range_expectation.value.strict_max_enabled, null)
          }
        }
        dynamic "regex_expectation" {
          for_each = rules.value.template == "regex_expectation" ? [rules.value.params] : []
          content {
            regex = try(regex_expectation.value.pattern, regex_expectation.value.regex)
          }
        }
        dynamic "set_expectation" {
          for_each = rules.value.template == "set_expectation" ? [rules.value.params] : []
          content {
            values = [for v in set_expectation.value.values : tostring(v)]
          }
        }
        dynamic "statistic_range_expectation" {
          for_each = rules.value.template == "statistic_range_expectation" ? [rules.value.params] : []
          content {
            statistic          = statistic_range_expectation.value.statistic
            min_value          = try(tostring(statistic_range_expectation.value.min_value), null)
            max_value          = try(tostring(statistic_range_expectation.value.max_value), null)
            strict_min_enabled = try(statistic_range_expectation.value.strict_min_enabled, null)
            strict_max_enabled = try(statistic_range_expectation.value.strict_max_enabled, null)
          }
        }
        dynamic "row_condition_expectation" {
          for_each = rules.value.template == "row_condition_expectation" ? [rules.value.params] : []
          content {
            sql_expression = row_condition_expectation.value.sql_expression
          }
        }
        dynamic "table_condition_expectation" {
          for_each = rules.value.template == "table_condition_expectation" ? [rules.value.params] : []
          content {
            sql_expression = table_condition_expectation.value.sql_expression
          }
        }
        dynamic "sql_assertion" {
          for_each = rules.value.template == "sql_assertion" ? [rules.value.params] : []
          content {
            sql_statement = sql_assertion.value.sql_statement
          }
        }
      }
    }

    post_scan_actions {
      # Central results table in the hub for the table's region (design §2.1, §3.6).
      # VERIFY IN BUILD (VA-35): scans in many projects can export to one hub table. Fallback: a
      # dq_results dataset per data project, read through a union view in the hub.
      bigquery_export {
        results_table = local.dq_results_table
      }
      # Native quality notification (design §3.6). VERIFY IN BUILD (VA-63): a group address
      # receives the report. VERIFY IN BUILD (VA-80): scoreThreshold is on the 0 to 100 scale.
      notification_report {
        recipients {
          emails = each.value.recipients
        }
        job_failure_trigger {}
        dynamic "score_threshold_trigger" {
          for_each = each.value.score_threshold == null ? [] : [each.value.score_threshold]
          content {
            score_threshold = score_threshold_trigger.value
          }
        }
      }
    }
  }
}

# The pipeline runs each on-demand scan after it loads the table (design §3.6 "Trigger"). The
# account that writes the table may run its scan. dataScanEditor is the smallest predefined role
# with dataplex.datascans.run on a scan. VERIFY IN BUILD (VA-58).
resource "google_dataplex_datascan_iam_member" "runner" {
  for_each = local.scans_ready

  project      = each.value.project
  location     = var.region
  data_scan_id = google_dataplex_datascan.dq[each.key].data_scan_id
  role         = "roles/dataplex.dataScanEditor"
  member       = "serviceAccount:${each.value.runner}"
}
