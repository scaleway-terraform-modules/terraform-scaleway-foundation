# Basic

Minimal setup on an Organization bootstrapped with the default options of `scripts/bootstrap.sh` (name `tf-foundation`, region `fr-par`, dedicated Project).

## Usage

1. Run `scripts/bootstrap.sh` on the Organization.
2. Add the backend configuration printed by the script to this example (for instance in a `backend.tf` file).
3. Configure the [scaleway provider](https://www.terraform.io/docs/providers/scaleway/index.html) with the API key stored in the `tf-foundation-ci-key` secret, and the Organization ID (for instance with the `SCW_DEFAULT_ORGANIZATION_ID` environment variable).

Then:

```sh
terraform init
terraform apply
```
