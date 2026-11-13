# Budget

Monthly spending limit on the Organization, with email alerts to the billing administrators.

This example sets a budget of 1000 euros per month, with alerts at 50%, 80%, 95% and 100% of it.
See [`main.tf`](main.tf) for every setting, with its default value.

## How alerts work

- Thresholds are percentages of the monthly limit. Without `thresholds`, alerts are sent at 80%, 95% and 100%.
- Each alert emails all the users of the `Billing Administrators` group. Applications of the group are ignored, as they have no email.
- The recipients are read at plan time: after adding or removing members of the group, run `terraform apply` to update them.
- The plan fails if no user of the group has an email address, as alerts would then reach nobody.
- Adding or removing a threshold only adds or removes that alert: the others are kept.

## Existing budget

The budget applies to the whole Organization.
If a budget was already created in the Scaleway console, import it before the first apply, with the `import` block commented out in [`main.tf`](main.tf).

## Usage

1. Bootstrap the Organization with `scripts/bootstrap.sh`, using its default options.
2. Make sure the `Billing Administrators` group has at least one user.
3. Follow the steps of the [basic example](../basic/README.md) to configure the backend and the provider.

Then:

```sh
terraform init
terraform plan
terraform apply
```
