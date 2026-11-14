# Bootstrap script

Before Terraform can run, an Organization needs a few resources: somewhere to store the Terraform state, and an identity for Terraform.
[`scripts/bootstrap.sh`](../scripts/bootstrap.sh) creates them. It is the first thing to run on a new Organization, and it can also be run on an existing Organization to adopt this operating model, or to repair the bootstrap (for example a deleted or broken API key).

The script is idempotent: every resource is looked up before being created, and a re-run only fixes what is missing or has drifted.

## Resources managed by the script

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

Terraform only reads these resources, with one exception: the policy of the state bucket is managed by the module (see the [module documentation](../README.md#terraform-state-bucket-policy)), and never by the script.

The API key gives full admin rights on the Organization: anyone who can read the secret is an Organization admin.
Only grant access to the bootstrap Project to Organization admins.

### Using the default Project

Scaleway creates every Organization with a Project named `default`, whose ID is the Organization ID.
With `--use-default-project`, the script puts the bucket and the secret in that Project instead of creating a dedicated one.
The script then uses the `default` Project as it is: it does not need the ownership mark on it, and never changes it.

This saves a Project, but the `default` Project is usually widely accessible: everyone who can read secrets in it can read the admin API key.
Prefer a dedicated Project unless access to the `default` Project is limited to Organization admins.

## Requirements

- bash 3.2 or later.
- The [Scaleway CLI](https://github.com/scaleway/scaleway-cli) (`scw`) 2.65 or later.
- Credentials of an Organization admin.

## Credentials

The script uses the same credentials as the `scw` CLI, either:

- the `SCW_ACCESS_KEY` and `SCW_SECRET_KEY` environment variables (recommended), ideally injected by a secret manager just for this run, or using a short-lived API key;
- or a `scw` profile, with `--profile <name>` (or the `SCW_PROFILE` environment variable).

Using both at the same time is refused, to avoid running with unexpected credentials.
The script never takes keys as arguments, and never writes the Terraform API key into your `scw` configuration.

## Running it

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
