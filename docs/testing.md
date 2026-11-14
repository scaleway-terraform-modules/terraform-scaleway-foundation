# Testing

The module and the bootstrap script must agree on the bootstrap resources: their names, their ownership tag and their settings.
No automated test checks them against Scaleway: test by hand on a test Organization any change to the script, or to how the module finds or checks the bootstrap resources, and run this procedure before each release.

The procedure leaves the test Organization as it found it, so it can be run again on the same Organization.

## Requirements

- An Organization used only for tests, already bootstrapped by the script.
- The credentials of an Organization admin, for the script and the `scw` commands.
- A Terraform configuration using the module from the working copy (`source` set to its path), with the backend configuration printed by the script, and the [environment variables](../README.md#environment-variables) of the Terraform API key.

Use the same script options on every run, and the matching module inputs.

## Procedure

1. Check the bootstrap with the script of the working copy:

   ```bash
   scripts/bootstrap.sh --organization-id <organization-id> --dry-run
   ```

   Expected: nothing to create or fix, apart from the changes under test.

2. Apply the script without `--dry-run`, if the previous step listed changes.

3. Run `terraform init -upgrade`, then `terraform plan` in the test configuration.

   Expected: no changes, and no warnings.

4. Make the bootstrap drift. Suspend versioning on the state bucket, make it public and delete its lifecycle rules, and remove the protection of the secret:

   ```bash
   scw object bucket update name=<state-bucket> region=<region> enable-versioning=false acl=public-read
   scw object bucket-lifecycle delete <state-bucket> region=<region>
   scw secret secret unprotect secret-id=<secret-id> region=<region>
   ```

   The secret ID is printed by the script, or by `scw secret secret list name=<name>-ci-key region=<region>`.

5. Run `terraform plan` again.

   Expected: no changes, and one warning for the bucket versioning and one for the secret protection.
   The module does not check the ACL of the bucket: the script repairs it.

6. Run the script again, without `--dry-run`.

   Expected: it enables versioning and sets the private ACL on the bucket, sets its lifecycle rules with the default retention, and protects the secret again.

7. Run `terraform plan` a last time.

   Expected: no changes, and no warnings.

8. Change the state retention, then run the script again without the option:

   ```bash
   scripts/bootstrap.sh --organization-id <organization-id> --state-retention never
   scripts/bootstrap.sh --organization-id <organization-id> --dry-run
   ```

   Expected: the first run sets the lifecycle rules without expiration of old versions, and the dry run reports them as they are, with nothing to change.
   Run the script with `--state-retention` and the retention shown by step 1 to restore it.
