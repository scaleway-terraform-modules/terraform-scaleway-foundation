# These inputs must match the options used with scripts/bootstrap.sh: the module uses
# them to find the resources created by the script. The Organization is the one set in
# the provider configuration.

variable "name" {
  type        = string
  description = "Name of the bootstrap resources (the --name of scripts/bootstrap.sh)."
  default     = "tf-foundation"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,37}[a-z0-9])?$", var.name))
    error_message = "name must be 1 to 39 lowercase letters, digits and hyphens, starting and ending with a letter or a digit."
  }
}

variable "region" {
  type        = string
  description = "Region of the Terraform state bucket (the region used by scripts/bootstrap.sh)."
  default     = "fr-par"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]{3}$", var.region))
    error_message = "region must be a Scaleway region, such as fr-par."
  }
}

variable "use_default_project" {
  type        = bool
  description = "Whether scripts/bootstrap.sh was run with --use-default-project."
  default     = false
}

variable "budget" {
  type = object({
    limit      = number
    enabled    = optional(bool, true)
    thresholds = optional(list(number), [80, 95, 100])
  })
  description = "Monthly spending limit of the Organization, in euros, and the thresholds (percentages of the limit) at which the members of the Billing Administrators group are notified by email. Leave null to manage no budget."
  default     = null

  validation {
    condition     = var.budget == null ? true : var.budget.limit > 0
    error_message = "budget.limit must be a positive amount, in euros."
  }

  validation {
    condition     = var.budget == null ? true : alltrue([for threshold in var.budget.thresholds : threshold > 0 && threshold <= 100])
    error_message = "budget.thresholds must be percentages, greater than 0 and up to 100."
  }

  validation {
    condition     = var.budget == null ? true : length(distinct(var.budget.thresholds)) == length(var.budget.thresholds)
    error_message = "budget.thresholds must not contain duplicates."
  }
}
