variable "business" {
  description = "Business domain name, for example customer."
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

variable "region" {
  description = "Deployment region."
  type        = string
}

variable "tf_state_bucket" {
  description = "Terraform state bucket that holds outputs/dda-<business>/<env>/outputs.json."
  type        = string
}

variable "billing_project" {
  description = "Quota project for API calls."
  type        = string
}

variable "repo_root" {
  description = "Path from this stack to the repository root."
  type        = string
  default     = "../../.."
}
