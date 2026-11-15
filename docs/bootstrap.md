# Bootstrap script

Before Terraform can run, an Organization needs a few resources: somewhere to store the Terraform state, and an identity for Terraform.
[`scripts/bootstrap.sh`](../scripts/bootstrap.sh) creates them. It is the first thing to run on a new Organization, and it can also be run on an existing Organization to adopt this operating model, or to repair the bootstrap (for example a deleted or broken API key).

The script is idempotent: every resource is looked up before being created, and a re-run only fixes what is missing or has drifted.

## Resources managed by the script

Resource names derive from `--name` (default: `tf-foundation`):

| Resource | Name | Settings enforced |
|---|---|---|
| Project | `<name>` | — |
| Object Storage bucket for the Terraform state | `<name>-tfstate-<region>-<first 8 characters of the organization ID>` | versioning enabled, private, [lifecycle rules](#state-retention) |
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

> [!IMPORTANT]
> The API key gives full admin rights on the Organization: anyone who can read the secret is an Organization admin.
> Only grant access to the bootstrap Project to Organization admins.

### Using the default Project

Scaleway creates every Organization with a Project named `default`, whose ID is the Organization ID.
With `--use-default-project`, the script puts the bucket and the secret in that Project instead of creating a dedicated one.
The script then uses the `default` Project as it is: it does not need the ownership mark on it, and never changes it.

> [!WARNING]
> This saves a Project, but the `default` Project is usually widely accessible: everyone who can read secrets in it can read the admin API key.
> Prefer a dedicated Project unless access to the `default` Project is limited to Organization admins.

## Requirements

- bash 3.2 or later.
- The [Scaleway CLI](https://github.com/scaleway/scaleway-cli) (`scw`) 2.65 or later.
- Credentials of an Organization admin.

## Credentials

The script uses the same credentials as the `scw` CLI, either:

- the `SCW_ACCESS_KEY` and `SCW_SECRET_KEY` environment variables (recommended), ideally injected by a secret manager just for this run, or using a short-lived API key;
- or a `scw` profile, with `--profile <name>` (or the `SCW_PROFILE` environment variable).

Using both at the same time is refused, to avoid running with unexpected credentials.

### Environment variables

| Variable | Required | Use |
|---|---|---|
| `SCW_ACCESS_KEY` | Without a profile | Access key of an Organization admin. |
| `SCW_SECRET_KEY` | Without a profile | Secret key of an Organization admin. |
| `SCW_PROFILE` | No | `scw` profile to use, instead of `--profile`. Refused with `SCW_ACCESS_KEY` / `SCW_SECRET_KEY`. |
| `SCW_DEFAULT_REGION` | No | Region of the bucket and of the secret, when `--region` is not set. |
| `SCW_DEFAULT_ORGANIZATION_ID` | No | Only checked: the script stops if it differs from `--organization-id`. |

No other variable is needed: the Organization is always given with `--organization-id`.
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
`--state-retention` is only needed to change the [state retention](#state-retention).
The script shows who it is acting as and asks for confirmation before making changes; use `--yes` to skip the confirmation in non-interactive runs.
Run `scripts/bootstrap.sh --help` for all options.

At the end, the script prints the backend configuration to use for the Terraform state.
It needs Terraform 1.11 or later, and enables encryption of the state and state locking (`use_lockfile`).
The API key is stored in the secret, with the `access_key` and `secret_key` fields.

## State retention

Every apply writes a new version of the Terraform state, and every state lock writes and deletes a lock file: the versioning of the bucket keeps all of them.
The script sets three lifecycle rules on the bucket:

- old versions of the state expire 90 days after being replaced;
- the delete markers left once the old versions of a lock file have expired are removed;
- incomplete uploads are aborted after 7 days.

An old version is only counted from the moment it is replaced: after a long period without any apply, the version replaced by the next one is still kept for the whole retention.
It covers a broken state noticed late, at least a monthly cycle.

Change the retention with `--state-retention <days>`, 30 days at least, or `--state-retention never` to keep every version.
The script keeps the retention of the bucket on the next runs: the option does not have to be repeated.
Set the same value in the `state_retention` input of the module: it warns when the rules of the bucket differ from it.
Old versions are not moved to colder storage: states are small, and restoring one from Glacier would delay a recovery.

> [!WARNING]
> The lifecycle rules of the bucket are replaced as a whole: rules added by hand are removed, and the script warns before doing so.

## Retrieving the API key

The API key is meant for the CI running Terraform: store its two fields in the secrets of your CI.
The script prints the commands to read them, with the secret ID and region filled in.
They can be run again at any time, by anyone allowed to read the secret:

```bash
scw secret version access secret-id=<secret-id> revision=latest_enabled field=access_key raw=true region=<region>
scw secret version access secret-id=<secret-id> revision=latest_enabled field=secret_key raw=true region=<region>
```

The script never prints the secret key itself.
When it replaces the API key, it adds a new version to the secret and disables the previous one: update the CI secrets with the new values.

## Detecting drift

The script is the reference for the bootstrap: run it with `--dry-run` to check every resource it manages and list what it would create or fix, without changing anything.
Run it regularly, and after any manual change in the bootstrap Project or in the `Administrators` group.

The module also warns about part of this drift on every plan (see [bootstrap drift](../README.md#bootstrap-drift)), but it cannot detect everything.
In particular, if the Terraform IAM application leaves the `Administrators` group, it loses its rights: Terraform then fails with permission errors on its first reads, before reaching any warning.
Run the script with the credentials of an Organization admin, not with the Terraform API key, to add it back to the group.

## Contract with the module

The module relies on what the script creates: both must agree on the items below.
This list is maintained by hand: a pull request changing one of these items updates the script, the module and this list together (see [CONTRIBUTING.md](../CONTRIBUTING.md)).
The [manual test procedure](testing.md) checks that both sides agree on a real Organization.

### Inputs and names

The module inputs mirror the options of the script, with the same defaults and the same validation rules:

| Script option | Module input | Default | Used for |
|---|---|---|---|
| `--name` | `name` | `tf-foundation` | Names of the bootstrap resources. 1 to 39 lowercase letters, digits and hyphens. |
| `--region` | `region` | `fr-par` | Region of the state bucket and of the secret. |
| `--use-default-project` | `use_default_project` | `false` | Project holding the bucket and the secret: `<name>`, or the `default` Project, whose ID is the Organization ID. |
| `--state-retention` | `state_retention` | `90` | Retention of old state versions, `30` days at least, or `never`. |

Both sides build the same names from these values:

| Resource | Name | Module (`main.tf`) |
|---|---|---|
| Project | `<name>` | `data.scaleway_account_project.foundation` |
| State bucket | `<name>-tfstate-<region>-<first 8 characters of the Organization ID>` | `local.bucket_name` |
| Terraform IAM application | `<name>-ci` | `data.scaleway_iam_application.foundation` |
| Secret holding the API key | `<name>-ci-key` | `check.terraform_secret` |
| Group of the Terraform application | `Administrators` | `data.scaleway_iam_group.administrators` |

### Ownership tag

The script tags the resources it creates with `owner=foundation-bootscript`.
The module refuses a state bucket or a Terraform IAM application without it (`main.tf`).

### Settings checked by the module

The module warns, without stopping the plan, when a setting enforced by the script is lost:

| Setting | Value | Module |
|---|---|---|
| Versioning of the state bucket | enabled | `check.state_bucket_versioning` (`state.tf`) |
| Protection of the secret | protected | `check.terraform_secret` (`main.tf`) |
| Lifecycle rules of the state bucket | `delete-old-state-versions` (after the retention, absent with `never`), `delete-lockfile-leftovers`, and `abort-incomplete-uploads` (after 7 days), and no other rule | `check.state_bucket_lifecycle` (`state.tf`) |

### Exceptions

Settings enforced by the script but not checked by the module, on purpose:

| Setting | Reason |
|---|---|
| Membership of the Terraform IAM application in `Administrators` | The module cannot check it: without it, Terraform fails on its first reads, before any check. See [detecting drift](#detecting-drift). |
| Private ACL of the state bucket | The bucket policy managed by the module already restricts access whenever Terraform runs. The ACL matters when the policy is missing, which only the script's dry run can report. |
| API key, its default Project, and its storage in the secret | The module does not use them: the API key is given to Terraform by the CI. |
| Type of the secret (`key_value`) | Only used to retrieve the API key, outside Terraform. |
