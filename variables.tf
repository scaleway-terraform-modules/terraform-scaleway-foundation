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
