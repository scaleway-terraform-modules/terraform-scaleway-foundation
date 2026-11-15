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
        # The Terraform application is not a member of the Administrators group: it is
        # granted access here. It needs the state files, the configuration of the bucket
        # and its policy, and bucket policies cannot grant the policy actions alone: only
        # s3:* covers them. Its IAM policy, set by scripts/bootstrap.sh, limits what it
        # can actually do on the bucket.
        Sid       = "Terraform"
        Effect    = "Allow"
        Principal = { SCW = "application_id:${data.scaleway_iam_application.foundation.id}" }
        Action    = ["s3:*"]
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

# Lifecycle rules set by scripts/bootstrap.sh, found by the names it gives them: old
# versions of the state expire after the retention of --state-retention (no rule with
# "never"), delete markers left by state locks are removed, and incomplete uploads are
# aborted. Warn only: the module does not manage the bucket.
locals {
  state_lifecycle_rules = { for rule in data.scaleway_object_bucket.tfstate.lifecycle_rule : rule.id => rule }

  # Same value as INCOMPLETE_UPLOAD_DAYS in scripts/bootstrap.sh.
  state_incomplete_upload_days = 7

  state_lifecycle_rule_ids = concat(
    ["delete-lockfile-leftovers", "abort-incomplete-uploads"],
    var.state_retention == "never" ? [] : ["delete-old-state-versions"],
  )
}

check "state_bucket_lifecycle" {
  assert {
    condition     = try(local.state_lifecycle_rules["delete-lockfile-leftovers"].enabled && local.state_lifecycle_rules["delete-lockfile-leftovers"].expiration[0].expired_object_delete_marker, false)
    error_message = "Bucket '${local.bucket_name}' does not remove the delete markers left by state locks. Run `scripts/bootstrap.sh` again to set its lifecycle rules."
  }

  assert {
    condition     = try(local.state_lifecycle_rules["abort-incomplete-uploads"].enabled && local.state_lifecycle_rules["abort-incomplete-uploads"].abort_incomplete_multipart_upload_days == local.state_incomplete_upload_days, false)
    error_message = "Bucket '${local.bucket_name}' does not abort incomplete uploads after ${local.state_incomplete_upload_days} days. Run `scripts/bootstrap.sh` again to set its lifecycle rules."
  }

  assert {
    condition = (var.state_retention == "never"
      ? !contains(keys(local.state_lifecycle_rules), "delete-old-state-versions")
      : try(local.state_lifecycle_rules["delete-old-state-versions"].enabled && local.state_lifecycle_rules["delete-old-state-versions"].noncurrent_version_expiration[0].noncurrent_days == tonumber(var.state_retention), false)
    )
    error_message = "The retention of old state versions on bucket '${local.bucket_name}' does not match 'state_retention' (${var.state_retention}). Run `scripts/bootstrap.sh --state-retention ${var.state_retention}` to set it, or set 'state_retention' to the retention reported by the script."
  }

  assert {
    condition     = length(setsubtract(keys(local.state_lifecycle_rules), local.state_lifecycle_rule_ids)) == 0
    error_message = "Bucket '${local.bucket_name}' has lifecycle rules not set by `scripts/bootstrap.sh`, which may delete versions of the Terraform state. Run the script again to replace them."
  }
}
