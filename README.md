# Terraform / Scaleway

## Purpose

This repository is used to manage the foundation of a Scaleway Organization using terraform: first bootstrapped with a script, then managed by this module.

## Bootstrap

Before Terraform can run, an Organization needs a few resources: somewhere to store the Terraform state, and an identity for Terraform.
[`scripts/bootstrap.sh`](scripts/bootstrap.sh) creates them. It is the first thing to run on a new Organization, and it can also be run on an existing Organization to adopt this operating model, or to repair the bootstrap (for example a deleted or broken API key).

The script is idempotent: every resource is looked up before being created, and a re-run only fixes what is missing or has drifted.

### Resources managed by the script

Resource names derive from `--name` (default: `tf-foundation`):

| Resource | Name | Settings enforced |
|---|---|---|
| Project | `<name>` | — |
| Object Storage bucket for the Terraform state | `<name>-tfstate-<region>-<first 8 characters of the organization ID>` | versioning enabled, private |
| IAM application used by Terraform | `<name>-ci` | member of the `Administrators` group |
| API key of the IAM application | `<name>-ci` (in the description, API keys have no name) | default Project is the Project above |
| Secret Manager secret holding the API key | `<name>-ci-key` | type `key_value`, protected |

The name may only contain lowercase letters, digits and hyphens, must start and end with a letter or a digit, and is limited to 39 characters (bucket names are limited to 63).

The bucket and the secret are created in that Project, in the region resolved as follows:

1. `--region`;
2. the `SCW_DEFAULT_REGION` environment variable;
3. the default region of the `scw` profile, when credentials come from a profile;
4. `fr-par`.

Always run the script with the same name, region and Project options.
To protect the API key, the script stops if its secret already exists in another region or Project.

The script only manages resources marked with `owner=foundation-bootscript`: as a tag, or in the description for Projects and API keys, which have no tags.
If a resource with one of the names above exists without that mark, the script stops instead of taking it over.
It never deletes anything else; the only deletions are the API keys it created earlier and that were replaced.

Terraform only reads these resources, with one exception: the policy of the state bucket is managed by the module (see [Usage](#usage)), and never by the script.

The API key gives full admin rights on the Organization: anyone who can read the secret is an Organization admin.
Only grant access to the bootstrap Project to Organization admins.

#### Using the default Project

Scaleway creates every Organization with a Project named `default`, whose ID is the Organization ID.
With `--use-default-project`, the script puts the bucket and the secret in that Project instead of creating a dedicated one.
The script then uses the `default` Project as it is: it does not need the ownership mark on it, and never changes it.

This saves a Project, but the `default` Project is usually widely accessible: everyone who can read secrets in it can read the admin API key.
Prefer a dedicated Project unless access to the `default` Project is limited to Organization admins.

### Requirements

- bash 3.2 or later.
- The [Scaleway CLI](https://github.com/scaleway/scaleway-cli) (`scw`) 2.65 or later.
- Credentials of an Organization admin.

### Credentials

The script uses the same credentials as the `scw` CLI, either:

- the `SCW_ACCESS_KEY` and `SCW_SECRET_KEY` environment variables (recommended), ideally injected by a secret manager just for this run, or using a short-lived API key;
- or a `scw` profile, with `--profile <name>` (or the `SCW_PROFILE` environment variable).

Using both at the same time is refused, to avoid running with unexpected credentials.
The script never takes keys as arguments, and never writes the Terraform API key into your `scw` configuration.

### Running it

```bash
# Show what would change, without changing anything
scripts/bootstrap.sh --organization-id <organization-id> --dry-run

# Apply
scripts/bootstrap.sh --organization-id <organization-id>
```

`--organization-id` is required and must match the Organization of the credentials in use.
Add `--name <name>` and `--use-default-project` as needed, and keep them identical on every run.
The script shows who it is acting as and asks for confirmation before making changes; use `--yes` to skip the confirmation in non-interactive runs.
Run `scripts/bootstrap.sh --help` for all options.

At the end, the script prints the backend configuration to use for the Terraform state.
It needs Terraform 1.11 or later, and enables encryption of the state and state locking (`use_lockfile`).
The API key is stored in the secret, with the `access_key` and `secret_key` fields.

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

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform) | >= 1.11 |
| <a name="requirement_scaleway"></a> [scaleway](#requirement_scaleway) | >= 2.79.0 |

## Resources

| Name | Type |
|------|------|
| [scaleway_object_bucket_policy.tfstate](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/object_bucket_policy) | resource |
| [scaleway_account_project.bootstrap](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/data-sources/account_project) | data source |
| [scaleway_account_projects.organization](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/data-sources/account_projects) | data source |
| [scaleway_iam_application.ci](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/data-sources/iam_application) | data source |
| [scaleway_iam_group.administrators](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/data-sources/iam_group) | data source |
| [scaleway_object_bucket.tfstate](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/data-sources/object_bucket) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name"></a> [name](#input_name) | Name of the bootstrap resources (the --name of scripts/bootstrap.sh). | `string` | `"tf-foundation"` | no |
| <a name="input_region"></a> [region](#input_region) | Region of the Terraform state bucket (the region used by scripts/bootstrap.sh). | `string` | `"fr-par"` | no |
| <a name="input_use_default_project"></a> [use_default_project](#input_use_default_project) | Whether scripts/bootstrap.sh was run with --use-default-project. | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_administrators_group_id"></a> [administrators_group_id](#output_administrators_group_id) | ID of the Administrators IAM group. |
| <a name="output_organization_id"></a> [organization_id](#output_organization_id) | ID of the Organization, taken from the provider configuration. |
| <a name="output_project_id"></a> [project_id](#output_project_id) | ID of the Project holding the bootstrap resources. |
| <a name="output_state_bucket_name"></a> [state_bucket_name](#output_state_bucket_name) | Name of the Terraform state bucket. |
| <a name="output_terraform_application_id"></a> [terraform_application_id](#output_terraform_application_id) | ID of the IAM application used by Terraform. |
<!-- END_TF_DOCS -->

## Authors

Module is maintained with help from [the community](https://github.com/scaleway-terraform-modules/terraform-scaleway-foundation/graphs/contributors).

## License

Mozilla Public License 2.0 Licensed. See [LICENSE](https://github.com/scaleway-terraform-modules/terraform-scaleway-domain/tree/master/LICENSE) for full details.
