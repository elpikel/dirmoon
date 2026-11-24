---
status: accepted
---

# Accounts with open sign-up, and tenancy through memberships

The handover said v1 has one user and needs no accounts, only a shared password. The owner chose otherwise: dirmoon gets the same model as Ditstar. Anyone can sign up from the landing page; an email creates a User, a new Account and the Membership between them, and phx.gen.auth's magic link signs them in. Research Runs, Niches, Briefs, Produced Pages and Search Console Connections belong to one Account, the current Account is the User's first Membership's Account carried in the `Scope`, and every context function that touches them takes the Scope.

## Considered options

- **Shared password (`Plug.BasicAuth`), no accounts.** What the handover proposed; rejected by the owner, who wants the tool ready for other users without a data migration.
- **phx.gen.auth without sign-up, unscoped data.** Cheaper now, but every query would need scoping added later.
- **`users.account_id`.** Simpler, but moving to memberships later means a data migration and touching every query.
