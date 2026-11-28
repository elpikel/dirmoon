---
status: accepted
---

# Paid access: every Research Run spends from a paid Allowance, bought through Stripe

The owner decided (27 Nov 2026) that nothing in dirmoon is free: a User pays before the first research, either $10 once for a single research or $49 a month for 10. This replaces the "no billing or per-account limits" that came with ADR-0001's open sign-up; sign-up itself stays open. Each payment Stripe confirms becomes an Allowance row (a number of researches, with an end date for a subscription month and none for a single purchase), and starting a Research Run spends one research from an Allowance and records which. What an Account may still start is always "researches bought minus runs started", never a counter that is added to and subtracted from. Payment, card changes and cancelling happen on Stripe's hosted pages (Checkout and the customer portal), and dirmoon learns the outcome only from Stripe's signed webhook events, each stored as received.

## Considered options

- **A `researches_left` counter on the Account.** Less code, but a webhook delivered twice or two runs started at once corrupts it with no way to see why; rejected.
- **Ask Stripe on each request whether the Account has paid.** No local state, but every screen would wait on Stripe and a single purchase has no "active" state to ask about; rejected.
- **Our own payment form (Stripe Elements).** Full control of the look, but card data, 3-D Secure and invoices become dirmoon's code; rejected for the hosted pages.

## Consequences

- An Account marked Unpaid Access (a switch only the owner sets, from the server console) starts runs without an Allowance. Nothing on the site offers it.
- The Stripe Customer is created before the first checkout and stored on the Account, so every later event finds its Account whatever order Stripe delivers events in.
- A refund in Stripe does not take an Allowance back; the owner has no refund rule yet.
- The prices shown on the landing page live in dirmoon's config and the amounts charged live in Stripe's Prices; changing a price means changing both.
