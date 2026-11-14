# Policy of the Terraform state bucket: only the members of the Administrators group
# and the Terraform application can access the state.
#
# A bucket policy can only restrict access: a request must be allowed both by IAM and by
# the bucket policy, and anything the policy does not allow is denied.

locals {
  tfstate_resources = [local.bucket_name, "${local.bucket_name}/*"]

  # Requests without TLS match no statement, and are therefore denied.
  tls_only = { Bool = { "aws:SecureTransport" = "true" } }

  # Bucket policies cannot name a group: list its members. Sorted, so that a different
  # order returned by the API does not show up as a change.
  administrators = sort(concat(
    [for id in data.scaleway_iam_group.administrators.user_ids : "user_id:${id}"],
    [for id in data.scaleway_iam_group.administrators.application_ids : "application_id:${id}"],
  ))
}

resource "scaleway_object_bucket_policy" "tfstate" {
  bucket     = data.scaleway_object_bucket.tfstate.name
  project_id = local.project_id
  region     = var.region

  policy = jsonencode({
    Version = "2023-04-17"
    Id      = "${var.name}-tfstate"
    Statement = [
      {
        Sid       = "Administrators"
        Effect    = "Allow"
        Principal = { SCW = local.administrators }
        Action    = ["s3:*"]
        Resource  = local.tfstate_resources
        Condition = local.tls_only
      },
      {
        # Granted explicitly, so that Terraform keeps access to its own state even if
        # its application leaves the Administrators group. Without it, an apply could
        # lock Terraform out of the state it is about to save.
        Sid       = "Terraform"
        Effect    = "Allow"
        Principal = { SCW = "application_id:${data.scaleway_iam_application.foundation.id}" }
        Action    = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource  = local.tfstate_resources
        Condition = local.tls_only
      },
    ]
  })

  lifecycle {
    precondition {
      condition     = length(data.scaleway_iam_group.administrators.user_ids) > 0
      error_message = "The `Administrators` group has no users: the policy would leave only the Organization owner able to reach the Terraform state."
    }
  }
}

# Versioning is enabled by scripts/bootstrap.sh, and lets a corrupted or deleted state be
# restored. Warn only: the module does not manage the bucket.
check "state_bucket_versioning" {
  assert {
    condition     = try(data.scaleway_object_bucket.tfstate.versioning[0].enabled, false)
    error_message = "Versioning is not enabled on bucket '${local.bucket_name}': a corrupted or deleted Terraform state could not be restored. Run `scripts/bootstrap.sh` again to enable it."
  }
}
