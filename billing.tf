# Budget of the Organization: alerts are emailed to the members of the default
# "Billing Administrators" group when spending reaches each threshold.

locals {
  # Alerts are keyed by threshold, so that adding or removing a threshold does not
  # recreate the others.
  budget_thresholds = var.budget == null ? toset([]) : toset([for threshold in var.budget.thresholds : tostring(threshold)])

  # Applications of the group have no email: only users are notified. Membership
  # changes are applied on the next terraform apply.
  billing_emails = sort([
    for user in data.scaleway_iam_user.billing_administrators : user.email
    if user.email != null && user.email != ""
  ])
}

data "scaleway_iam_group" "billing_administrators" {
  count = var.budget == null ? 0 : 1

  name            = "Billing Administrators"
  organization_id = local.organization_id
}

data "scaleway_iam_user" "billing_administrators" {
  for_each = var.budget == null ? toset([]) : toset(data.scaleway_iam_group.billing_administrators[0].user_ids)

  user_id = each.value
}

resource "scaleway_billing_budget" "this" {
  count = var.budget == null ? 0 : 1

  organization_id   = local.organization_id
  consumption_limit = var.budget.limit
  enabled           = var.budget.enabled

  lifecycle {
    # Also checked when the budget is disabled: its alerts are kept, and need
    # recipients once it is enabled again.
    precondition {
      condition     = length(local.billing_emails) > 0
      error_message = "No email address found for the members of the `Billing Administrators` group: budget alerts would reach nobody. Add users to the group."
    }
  }
}

resource "scaleway_billing_budget_alert" "this" {
  for_each = local.budget_thresholds

  budget_id = scaleway_billing_budget.this[0].id
  threshold = tonumber(each.key)
}

resource "scaleway_billing_budget_alert_notification" "email" {
  for_each = local.budget_thresholds

  budget_alert_id = scaleway_billing_budget_alert.this[each.key].id
  email_addresses = local.billing_emails
}
