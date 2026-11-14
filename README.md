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
- Set the [environment variables](#environment-variables) below in the CI running Terraform.
- Set up the [scaleway provider](https://www.terraform.io/docs/providers/scaleway/index.html) in your tf file.
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

> [!WARNING]
> Keep `name`, `region` and `use_default_project` identical to the options of the bootstrap script, on every run.
> Changing them points the module to other bootstrap resources: it then moves the state bucket policy to the new bucket, and the previous bucket is no longer protected by it.
> To change them, bootstrap again with the new options, migrate the state to the new bucket (`terraform init -migrate-state` with the backend configuration printed by the script), then apply the module with the new inputs.
> The script refuses to move its secret to another region or Project: changing `region` or `use_default_project` also needs a new `name`.
> It never deletes the previous resources: delete them by hand once they are no longer used.

See the [examples](examples) folder for runnable configurations: [basic](examples/basic/README.md) setup with the default options, and [budget](examples/budget/README.md).

### Environment variables

Terraform uses the API key created by the bootstrap script, stored in the `<name>-ci-key` secret (see [how to retrieve it](docs/bootstrap.md#retrieving-the-api-key)).
The S3 backend and the Scaleway provider read it from different variables, so set both:

| Variable | Used by | Value |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | S3 backend | `access_key` field of the secret |
| `AWS_SECRET_ACCESS_KEY` | S3 backend | `secret_key` field of the secret |
| `SCW_ACCESS_KEY` | Scaleway provider | `access_key` field of the secret |
| `SCW_SECRET_KEY` | Scaleway provider | `secret_key` field of the secret |
| `SCW_DEFAULT_ORGANIZATION_ID` | Scaleway provider | ID of the Organization |

The S3 backend ignores the `SCW_*` variables, and the Scaleway provider ignores the `AWS_*` ones.
The provider settings can also come from its arguments or from a `scw` profile instead.

> [!IMPORTANT]
> The API key gives full admin rights on the Organization: anyone who can read the secret, or the CI secrets holding the key, is an Organization admin.
> Only give access to them to Organization admins.

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
| <a name="input_budget"></a> [budget](#input_budget) | Monthly spending limit of the Organization, in euros (`limit`), and the thresholds at which the members of the `Billing Administrators` group are notified by email (`thresholds`, default `[80, 95, 100]`). Thresholds are percentages of the limit, greater than 0 and up to 100, the range accepted by Scaleway budget alerts, and at least one is required. `enabled` (default `true`) disables the budget without deleting it. The group must have at least one user with an email address, even when the budget is disabled. Leave null to manage no budget. | ```object({ limit = number enabled = optional(bool, true) thresholds = optional(list(number), [80, 95, 100]) })``` | `null` | no |
| <a name="input_name"></a> [name](#input_name) | Name of the bootstrap resources: the `--name` option of `scripts/bootstrap.sh`. | `string` | `"tf-foundation"` | no |
| <a name="input_region"></a> [region](#input_region) | Region of the Terraform state bucket: the region used by `scripts/bootstrap.sh`, e.g. `fr-par`. | `string` | `"fr-par"` | no |
| <a name="input_use_default_project"></a> [use_default_project](#input_use_default_project) | Whether `scripts/bootstrap.sh` was run with the `--use-default-project` option. | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_administrators_group_id"></a> [administrators_group_id](#output_administrators_group_id) | ID of the `Administrators` IAM group. |
| <a name="output_budget_id"></a> [budget_id](#output_budget_id) | ID of the Organization budget. Null when `budget` is null. |
| <a name="output_organization_id"></a> [organization_id](#output_organization_id) | ID of the Organization, taken from the provider configuration. |
| <a name="output_project_id"></a> [project_id](#output_project_id) | ID of the Project holding the bootstrap resources. |
| <a name="output_state_bucket_name"></a> [state_bucket_name](#output_state_bucket_name) | Name of the Terraform state bucket. |
| <a name="output_terraform_application_id"></a> [terraform_application_id](#output_terraform_application_id) | ID of the IAM application used by Terraform. |
<!-- END_TF_DOCS -->

## Authors

Module is maintained with help from [the community](https://github.com/scaleway-terraform-modules/terraform-scaleway-foundation/graphs/contributors).

## License

Mozilla Public License 2.0 Licensed. See [LICENSE](https://github.com/scaleway-terraform-modules/terraform-scaleway-foundation/tree/main/LICENSE) for full details.
