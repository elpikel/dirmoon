---
status: accepted
---

# Market data is shared across Accounts

Phrases (`keywords`), their Volumes (`keyword_metrics`) and SERP Snapshots (`serp_snapshots`) are public market data, not customer data, so they are stored once for all Accounts. A Research Run in any Account reuses a Volume or SERP Snapshot fetched in the last 30 days for the same Phrase and location instead of buying it again, and the phrase database grows across runs. Everything that says what a customer is working on stays per Account: the Research Run and its input, which Phrases a run kept or rejected, Niches, Competition labels (they depend on the business), Search Console data, Briefs and Produced Pages. A run records only the API Cost it actually incurred, so a run that reused cached data shows a lower cost.

## Considered options

- **Per-Account copies.** Simpler access rule (nothing crosses Accounts), but every Account pays again for the same Volumes and the shared database the handover asks for never forms.

## Consequences

The shared tables must never hold anything that identifies an Account or its business: no description, domain, run id or Search Console figure.
