provider "scaleway" {}

module "foundation" {
  source = "../.."

  budget = {
    # Monthly spending limit of the whole Organization, in euros.
    limit = 1000

    # Percentages of the limit at which the users of the "Billing Administrators" group
    # are emailed. Optional: defaults to [80, 95, 100]. At least one threshold must be
    # set, each between 0 (excluded) and 100.
    thresholds = [50, 80, 95, 100]

    # Optional, defaults to true. Set to false to disable the budget without deleting
    # it, and keep its alerts configured. The "Billing Administrators" group must
    # still have a user with an email address.
    # enabled = false
  }
}

# If a budget was already created in the Scaleway console, import it before the first
# apply, instead of creating a second one. Its ID is shown in the console.
#
# import {
#   to = module.foundation.scaleway_billing_budget.this[0]
#   id = "<budget-id>"
# }
