output "organization_id" {
  description = "ID of the Organization managed by the module."
  value       = module.foundation.organization_id
}

output "project_id" {
  description = "ID of the Project holding the bootstrap resources."
  value       = module.foundation.project_id
}

output "state_bucket_name" {
  description = "Name of the Terraform state bucket."
  value       = module.foundation.state_bucket_name
}

output "terraform_application_id" {
  description = "ID of the IAM application used by Terraform."
  value       = module.foundation.terraform_application_id
}
