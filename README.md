# Terraform / Scaleway

## Purpose

This repository is used to manage the foundation of a Scaleway Organization using terraform: first bootstrapped with a script, then managed by this module.

## Bootstrap

Before Terraform can run, an Organization needs somewhere to store the Terraform state, and an identity for Terraform.
[`scripts/bootstrap.sh`](scripts/bootstrap.sh) creates them: a Project, a state bucket, an IAM application member of the `Administrators` group, and its API key, stored in Secret Manager.
It is idempotent, and can also adopt an existing Organization or repair a broken bootstrap.

```bash
scripts/bootstrap.sh --organization-id <organization-id> --dry-run
scripts/bootstrap.sh --organization-id <organization-id>
```

See the [bootstrap documentation](docs/bootstrap.md) for the resources it manages, its options and the credentials it needs.

## Usage

- Bootstrap the Organization with [`scripts/bootstrap.sh`](#bootstrap), and use the backend configuration it prints.
- Setup the [scaleway provider](https://www.terraform.io/docs/providers/scaleway/index.html) in your tf file, with the API key stored in the `<name>-ci-key` secret and the Organization ID (provider `organization_id` argument, `SCW_DEFAULT_ORGANIZATION_ID` environment variable or `scw` profile).
- Include this module in your tf file. Refer to [documentation](https://www.terraform.io/docs/modules/sources.html#generic-git-repository).

```hcl
module "foundation" {
  source  = "scaleway-terraform-modules/foundation/scaleway"
  version = "0.0.1"

  # Only if scripts/bootstrap.sh was run with other values than the defaults:
  # name                = "tf-foundation"
  # region              = "fr-par"
  # use_default_project = false
}
```

The module works on the Organization set in the provider configuration, and fails at plan time if none is set.
The inputs must match the options used with the bootstrap script: the module finds the bootstrap resources from them, and fails if they do not exist.

### Terraform state bucket policy

The module sets a policy on the state bucket, so that only these principals can access the Terraform state:

- the members of the `Administrators` group (users and applications), with full access;
- the Terraform IAM application (`<name>-ci`), with the access the S3 backend needs, even if it leaves the `Administrators` group.

All requests must use TLS.

A bucket policy can only restrict access: a request must also be allowed by IAM.
Bucket policies cannot name a group, so the policy lists the group members: after changing the members of `Administrators`, run `terraform apply` to update it.
The plan fails if the group has no users, as only the Organization owner could then reach the state.
The Organization owner can always replace or delete the policy, should access be lost.

### Budget

With the optional `budget` input, the module sets a monthly spending limit on the Organization, and emails the users of the `Billing Administrators` group when spending reaches thresholds expressed as percentages of that limit (80%, 95% and 100% by default).

See the [budget example](examples/budget/README.md) for the settings, how alerts work, and how to import a budget already created in the Scaleway console.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform) | >= 1.11 |
| <a name="requirement_scaleway"></a> [scaleway](#requirement_scaleway) | >= 2.79.0 |

## Resources

| Name | Type |
|------|------|
| [scaleway_billing_budget.this](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/billing_budget) | resource |
| [scaleway_billing_budget_alert.this](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/billing_budget_alert) | resource |
| [scaleway_billing_budget_alert_notification.email](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/billing_budget_alert_notification) | resource |
| [scaleway_object_bucket_policy.tfstate](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/object_bucket_policy) | resource |
| [scaleway_account_project.foundation](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/data-sources/account_project) | data source |
| [scaleway_account_projects.organization](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/data-sources/account_projects) | data source |
| [scaleway_iam_application.foundation](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/data-sources/iam_application) | data source |
| [scaleway_iam_group.administrators](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/data-sources/iam_group) | data source |
| [scaleway_iam_group.billing_administrators](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/data-sources/iam_group) | data source |
| [scaleway_iam_user.billing_administrators](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/data-sources/iam_user) | data source |
| [scaleway_object_bucket.tfstate](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/data-sources/object_bucket) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_budget"></a> [budget](#input_budget) | Monthly spending limit of the Organization, in euros, and the thresholds (percentages of the limit) at which the members of the Billing Administrators group are notified by email. Leave null to manage no budget. | ```object({ limit = number enabled = optional(bool, true) thresholds = optional(list(number), [80, 95, 100]) })``` | `null` | no |
| <a name="input_name"></a> [name](#input_name) | Name of the bootstrap resources (the --name of scripts/bootstrap.sh). | `string` | `"tf-foundation"` | no |
| <a name="input_region"></a> [region](#input_region) | Region of the Terraform state bucket (the region used by scripts/bootstrap.sh). | `string` | `"fr-par"` | no |
| <a name="input_use_default_project"></a> [use_default_project](#input_use_default_project) | Whether scripts/bootstrap.sh was run with --use-default-project. | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_administrators_group_id"></a> [administrators_group_id](#output_administrators_group_id) | ID of the Administrators IAM group. |
| <a name="output_budget_id"></a> [budget_id](#output_budget_id) | ID of the Organization budget, or null when no budget is managed. |
| <a name="output_organization_id"></a> [organization_id](#output_organization_id) | ID of the Organization, taken from the provider configuration. |
| <a name="output_project_id"></a> [project_id](#output_project_id) | ID of the Project holding the bootstrap resources. |
| <a name="output_state_bucket_name"></a> [state_bucket_name](#output_state_bucket_name) | Name of the Terraform state bucket. |
| <a name="output_terraform_application_id"></a> [terraform_application_id](#output_terraform_application_id) | ID of the IAM application used by Terraform. |
<!-- END_TF_DOCS -->

## Authors

Module is maintained with help from [the community](https://github.com/scaleway-terraform-modules/terraform-scaleway-foundation/graphs/contributors).

## License

Mozilla Public License 2.0 Licensed. See [LICENSE](https://github.com/scaleway-terraform-modules/terraform-scaleway-domain/tree/master/LICENSE) for full details.
