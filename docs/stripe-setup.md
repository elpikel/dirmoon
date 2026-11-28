# Stripe setup

What to do in the Stripe Dashboard so dirmoon can take payments. Written from Stripe's documentation as read on 28 Nov 2026 (`.claude/work/paid-access/stripe-notes.md`); dirmoon has never been run against Stripe, live or sandbox. Points marked *unverified* are not stated on the Stripe pages read; check them in a sandbox first.

Do everything below once in a sandbox and once in live mode: Stripe keeps a separate product catalog, webhook endpoints, signing secrets and customer portal settings for each.

## 1. The secret key

`STRIPE_SECRET_KEY` is Stripe's secret API key: `sk_test_…` in a sandbox, `sk_live_…` in live mode. dirmoon sends it as a Bearer token and only to `https://api.stripe.com`. Stripe recommends restricted keys (`rk_live_…`) in live mode; which permissions dirmoon's three calls (create a Customer, a Checkout Session and a customer portal session) need is not checked (*unverified*).

## 2. The product and its two Prices

In the Dashboard: **More → Product catalog → + Add product**. Give it a name, then add a price:

1. Pricing model **Flat-rate pricing**, then **One time**.
2. The amount and the currency. dirmoon shows its prices in USD.
3. **Include tax in price**: the price's tax behaviour (see section 6). It can't be changed once set to inclusive or exclusive.
4. **Add product**.

Open the product and add a second price the same way, this time **Recurring** with a monthly **Billing period**. One product with both prices works, and so do two products.

Copy each Price id (`price_…`): the one-off price into `STRIPE_PRICE_SINGLE`, the monthly price into `STRIPE_PRICE_MONTHLY`. Where the Dashboard shows a price's id is *unverified* (Stripe's pages don't say; it should be on the product's page next to each price, and `GET /v1/prices` lists them).

A price's amount can't be changed after it is created: to change a price, create a new one, archive the old one and put the new id in the environment. A sandbox product copied to live mode ("Copy to live mode") gets new ids there.

**Two places for a price.** The amounts Stripe charges are in these Prices. The prices dirmoon shows (landing page, plan screen) are `single_price` and `monthly_price` in `config :dirmoon, Dirmoon.Billing`, and the number of researches a paid month gives is its `monthly_researches`. dirmoon never reads the amount Stripe charged, so the two must be kept equal by hand (ADR-0004).

## 3. The webhook endpoint

dirmoon learns about every payment only from Stripe's webhook. Create an endpoint in the Dashboard:

- **URL:** `https://<your domain>/webhooks/stripe`.
- **API version:** `2026-11-18.endive`, the version dirmoon pins (`api_version` in `config :dirmoon, Dirmoon.Billing.Stripe.HTTP`). The Dashboard offers the account's default version or the latest one; any other version needs the API (the `api_version` parameter when creating the endpoint). dirmoon compares only the release name after the dot (`endive`). A payment or Subscription event of another release is stored but not acted on: dirmoon answers 422, Stripe retries, and every retry fails the same way, since an event keeps the version it was made with. Set the version before the first payment.
- **Events:** snapshot events (the classic events with the object in `data.object`), not thin ones. Select exactly these:
  - `checkout.session.completed`
  - `checkout.session.async_payment_succeeded`
  - `invoice.paid`
  - `customer.subscription.created`
  - `customer.subscription.updated`
  - `customer.subscription.deleted`

Then copy the endpoint's signing secret (`whsec_…`, shown in Workbench → Webhooks) into `STRIPE_WEBHOOK_SECRET`. Without it the webhook answers 503 and Stripe keeps retrying (in live mode for up to three days).

## 4. The customer portal

"Manage plan" on the plan screen sends the User to Stripe's customer portal, where they change their card or cancel. Before it works, choose what customers may do at https://dashboard.stripe.com/settings/billing/portal and save it, in the sandbox and again in live mode (each mode has its own settings). What Stripe answers when nothing has been saved in that mode is *unverified*; dirmoon then shows "That didn't work. Please try again."

dirmoon sends the return address itself (the plan screen), so no default return URL is needed. The portal needs a product catalog only if customers may switch plans or change quantities; dirmoon has one plan. If pausing is turned on, a paused plan shows on the plan screen as "Your monthly plan needs your attention. Open Manage plan to see why."

## 5. Invoices

A monthly plan gets an invoice from Stripe every month. A one-off payment gets a receipt, not an invoice: dirmoon does not ask Checkout for one, since Stripe prices post-purchase invoices separately from Invoicing.

## 6. VAT and Stripe Tax

Off by default: `automatic_tax: false` in `config :dirmoon, Dirmoon.Billing.Stripe.HTTP`, so Checkout charges the Price's amount and no tax is worked out. To turn it on, set up Stripe Tax first, then set `automatic_tax: true`; dirmoon then asks Checkout for automatic tax and saves the billing address Checkout collects on the Customer (`customer_update[address]=auto`). Stripe Tax needs:

1. The head office address, at https://dashboard.stripe.com/settings/tax.
2. A preset product tax code (or a tax code on the product).
3. A default tax behaviour, or a tax behaviour on each Price. With **exclusive** tax is added on top of the price, so the customer pays more than the price dirmoon shows; with **inclusive** they pay the price shown.
4. A registration with each tax authority you collect for, added under Tax → Locations. Stripe collects tax only where a registration exists.

Whether tax settings and registrations are separate for sandbox and live is *unverified*; check both.

## 7. Trying it locally

Locally the Stripe CLI forwards events, and no Dashboard endpoint is needed:

```sh
stripe login
stripe listen --latest \
  --events checkout.session.completed,checkout.session.async_payment_succeeded,invoice.paid,customer.subscription.created,customer.subscription.updated,customer.subscription.deleted \
  --forward-to localhost:4000/webhooks/stripe
```

It prints `Ready! Your webhook signing secret is 'whsec_…'`: export that as `STRIPE_WEBHOOK_SECRET` (it stays the same between restarts), with a sandbox `STRIPE_SECRET_KEY` and the sandbox Price ids, and restart the server. `--latest` sends events in the latest API version instead of the account's default; dirmoon needs the `endive` release.

Accounts signed up in dev after this change have Unpaid Access (Accounts that existed before the migration have none and need no change here), so to try paying with a newer Account, take it off first (`iex -S mix`, then `Dirmoon.Billing.set_unpaid_access("you@example.com", false)`). Then open "Plan", buy, and pay on Stripe's page with the test card `4242 4242 4242 4242`, any future expiry date and any three-digit CVC (sandbox only). With the CLI, Checkout sends you back to the plan screen at once instead of waiting for the webhook, so the screen may still be confirming the payment when you arrive; it updates when the event comes in.

`stripe trigger checkout.session.completed` and the like make real sandbox objects with Stripe's own sample data, without the `client_reference_id` dirmoon sets and without your Price ids, so they add no research to your Account. Use a real checkout to test a payment.

## 8. Going live

In live mode: the live secret key, the two live Price ids (new ids, see section 2), a live webhook endpoint (its own signing secret), the customer portal saved in live mode and, if wanted, Stripe Tax. Set the four variables on the server and restart.
