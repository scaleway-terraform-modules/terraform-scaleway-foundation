# Foundation of a Scaleway Organization, applied after scripts/bootstrap.sh.
#
# The resources created by the bootstrap script (Project, state bucket, IAM application,
# API key and secret) belong to the script: this module only reads them. The one
# exception is the policy of the state bucket, managed here and never by the script.

locals {
  organization_id = data.scaleway_account_projects.organization.organization_id

  project_id = var.use_default_project ? local.organization_id : data.scaleway_account_project.foundation[0].id

  # Same naming rule as scripts/bootstrap.sh.
  bucket_name = "${var.name}-tfstate-${var.region}-${substr(local.organization_id, 0, 8)}"
}

# --- Organization --------------------------------------------------------------------

# Without organization_id, this data source uses the Organization of the provider
# configuration and returns it. Unlike scaleway_config, it does not expose credentials,
# which would otherwise be stored in the state.
data "scaleway_account_projects" "organization" {}

# --- Resources created by scripts/bootstrap.sh (read only) ---------------------------

data "scaleway_account_project" "foundation" {
  count = var.use_default_project ? 0 : 1

  name            = var.name
  organization_id = local.organization_id
}

data "scaleway_iam_application" "foundation" {
  name            = "${var.name}-ci"
  organization_id = local.organization_id

  # The state bucket policy gives this application access to the Terraform state: never
  # give it to an application the script did not create. The script tags it with
  # owner=foundation-bootscript.
  lifecycle {
    postcondition {
      condition     = try(contains(self.tags, "owner=foundation-bootscript"), false)
      error_message = "IAM application '${var.name}-ci' has no `owner=foundation-bootscript` tag: it was not created by `scripts/bootstrap.sh`. Check that 'name' matches the `--name` option of the script."
    }
  }
}

data "scaleway_object_bucket" "tfstate" {
  name       = local.bucket_name
  project_id = local.project_id
  region     = var.region

  # The module replaces the policy of this bucket: never do it on a bucket the script
  # did not create. The script tags it with owner=foundation-bootscript.
  lifecycle {
    postcondition {
      condition     = try(self.tags["owner"], null) == "foundation-bootscript"
      error_message = "Bucket '${local.bucket_name}' has no `owner=foundation-bootscript` tag: it was not created by `scripts/bootstrap.sh`. Check that 'name', 'region' and 'use_default_project' match the options of the script."
    }
  }
}

# The secret created by scripts/bootstrap.sh holds the only copy of the Terraform API
# key, and is protected against deletion. Read inside the check, so that a deleted secret
# is reported as a warning instead of failing the plan.
check "terraform_secret" {
  data "scaleway_secret" "terraform" {
    name       = "${var.name}-ci-key"
    project_id = local.project_id
    region     = var.region
  }

  assert {
    condition     = data.scaleway_secret.terraform.protected
    error_message = "Secret '${var.name}-ci-key', holding the Terraform API key, is not protected: it can be deleted, and the key with it. Run `scripts/bootstrap.sh` again to protect it."
  }
}

# --- Default Scaleway resources (read only) ------------------------------------------

data "scaleway_iam_group" "administrators" {
  name            = "Administrators"
  organization_id = local.organization_id
}
