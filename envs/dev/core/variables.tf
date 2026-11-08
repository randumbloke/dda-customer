variable "business" {
  description = "Business domain name, for example customer. The data domain ID is <business>-<env>."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9]*$", var.business))
    error_message = "business must be lower-case letters and digits."
  }
}

variable "env" {
  description = "Environment."
  type        = string
  validation {
    condition     = contains(["dev", "test", "uat", "prod"], var.env)
    error_message = "env must be dev, test, uat or prod."
  }
}

variable "tier" {
  description = "Hub tier that serves this environment."
  type        = string
  validation {
    condition     = contains(["nonprod", "prod"], var.tier)
    error_message = "tier must be nonprod or prod."
  }
}

variable "region" {
  description = "Deployment region (single region in phase 1)."
  type        = string
}

variable "tf_state_bucket" {
  description = "Terraform state bucket that holds bootstrap/estate.json and the outputs/ files (design §6.13.3)."
  type        = string
}

variable "billing_project" {
  description = "Quota project for API calls."
  type        = string
}

variable "repo_root" {
  description = "Path from this stack to the repository root, where datasets.yaml, products/, dq/ and pipelines/ live."
  type        = string
  default     = "../../.."
}

variable "commit_sha" {
  description = "Commit being applied, recorded in published product definitions. Empty omits it."
  type        = string
  default     = ""
}

variable "components" {
  description = "Component flags by phase (design §6.17). The domain stack reads access_request_gate and reconciler."
  type = object({
    classifier          = bool
    steward_inbox       = bool
    access_request_gate = bool
    reconciler          = bool
    explainer           = bool
    scan_generator      = bool
    sdp_notifications   = bool
    access_request_sink = bool
    data_access_sink    = bool
    policy_tags         = bool
    evaluator_modules   = list(string)
  })
}

variable "pipeline" {
  description = "P6-39 reference pipeline jobs (Cloud Run jobs and Cloud Scheduler)."
  type = object({
    enabled  = bool
    image    = string
    schedule = string
    timezone = string
  })
  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.pipeline.image))
    error_message = "pipeline.image must be referenced by digest (<image>@sha256:...): dda-pipelines tags are immutable."
  }
}
