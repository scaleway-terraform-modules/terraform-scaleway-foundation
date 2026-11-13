# Foundation of a Scaleway Organization, applied after scripts/bootstrap.sh.
#
# The resources created by the bootstrap script (Project, state bucket, IAM application,
# API key and secret) belong to the script: this module only reads them. The one
# exception is the policy of the state bucket, managed here and never by the script.

locals {
  organization_id = data.scaleway_account_projects.organization.organization_id

  project_id = var.use_default_project ? local.organization_id : data.scaleway_account_project.bootstrap[0].id

  # Same naming rule as scripts/bootstrap.sh.
  bucket_name = "${var.name}-tfstate-${var.region}-${substr(local.organization_id, 0, 8)}"
}

# --- Organization --------------------------------------------------------------------

# Without organization_id, this data source uses the Organization of the provider
# configuration and returns it. Unlike scaleway_config, it does not expose credentials,
# which would otherwise be stored in the state.
data "scaleway_account_projects" "organization" {}

# --- Resources created by scripts/bootstrap.sh (read only) ---------------------------

data "scaleway_account_project" "bootstrap" {
  count = var.use_default_project ? 0 : 1

  name            = var.name
  organization_id = local.organization_id
}

data "scaleway_iam_application" "ci" {
  name            = "${var.name}-ci"
  organization_id = local.organization_id
}

data "scaleway_object_bucket" "tfstate" {
  name       = local.bucket_name
  project_id = local.project_id
  region     = var.region
}

# --- Default Scaleway resources (read only) ------------------------------------------

data "scaleway_iam_group" "administrators" {
  name            = "Administrators"
  organization_id = local.organization_id
}
