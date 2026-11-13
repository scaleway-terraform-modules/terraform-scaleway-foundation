output "organization_id" {
  description = "ID of the Organization, taken from the provider configuration."
  value       = local.organization_id
}

output "project_id" {
  description = "ID of the Project holding the bootstrap resources."
  value       = local.project_id
}

output "state_bucket_name" {
  description = "Name of the Terraform state bucket."
  value       = data.scaleway_object_bucket.tfstate.name
}

output "terraform_application_id" {
  description = "ID of the IAM application used by Terraform."
  value       = data.scaleway_iam_application.foundation.id
}

output "administrators_group_id" {
  description = "ID of the Administrators IAM group."
  value       = data.scaleway_iam_group.administrators.id
}

output "budget_id" {
  description = "ID of the Organization budget, or null when no budget is managed."
  value       = one(scaleway_billing_budget.this[*].id)
}
