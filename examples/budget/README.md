# Budget

Monthly spending limit on the Organization, with email alerts to the billing administrators.

This example sets a budget of 1000 euros per month, with alerts at 50%, 80%, 95% and 100% of it.
See [`main.tf`](main.tf) for every setting, with its default value.

## How alerts work

- Thresholds are percentages of the monthly limit. Without `thresholds`, alerts are sent at 80%, 95% and 100%. At least one threshold is required: to manage no budget, set `budget` to null.
- Each alert emails all the users of the `Billing Administrators` group, and the extra addresses of `additional_emails`. Applications of the group are ignored, as they have no email.
- Each alert also calls the URLs of the `budget_webhook_urls` input, if any. They need a budget, and must use HTTPS.
- At most 10 thresholds can be set, the maximum number of alerts of a Scaleway budget.
- The recipients are read at plan time: after adding or removing members of the group, run `terraform apply` to update them.
- The plan fails if no user of the group has an email address, as alerts would then reach nobody. This also applies to a disabled budget (`enabled = false`): its alerts are kept, and need recipients once it is enabled again.
- Adding or removing a threshold only adds or removes that alert: the others are kept.

## Webhooks

Scaleway sends each webhook an HTTP POST request with a JSON body holding the threshold reached, in percent, and the start date of the invoice period ([Scaleway documentation](https://www.scaleway.com/en/docs/billing/how-to/use-billing-alerts/)):

- The body does not name the Organization: use a different URL for each Organization sending to the same system.
- The body has a fixed format: the receiving system must accept any JSON, such as the generic webhook of an alerting system. Tools expecting their own format need a relay in between.
- Requests are not signed: anyone knowing a URL can call it. This is why the input is sensitive: keep the URLs out of version control, and pass them as a sensitive variable, e.g. from the secrets of the CI.

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
