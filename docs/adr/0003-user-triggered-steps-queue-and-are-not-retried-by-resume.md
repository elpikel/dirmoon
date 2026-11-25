---
status: proposed
---

# User-triggered Steps are queued, and resume does not retry them after a final failure

Steps 8 (Brief) and 9 (Publish) start on a user action, not automatically after the previous Step. When one is requested its Step becomes `queued` (job inserted, not started), so that stopping a run before the job starts and then resuming it runs the job again and the page isn't left stuck on "writing" or "publishing". Only one Step of a run is in progress at a time: choosing a Niche or publishing is refused while another Step is queued or running (`Research.idle?/1`). After a FINAL failure of Step 8 or 9 the worker has already put the page back (a failed Brief, or the previously ready or published page), so resuming the run does not retry that Step; the user chooses the Niche or publishes again. This departs from acceptance criterion AC-R11 ("resume enqueues the first Step that isn't done or skipped") for these two Steps.

## Considered options

- **Treat a requested Step 8/9 like any waiting Step.** It was indistinguishable from a Step never requested, so stop-then-resume stranded the page with no job. Found in review, three times in different orders.
- **Resume retries a finally-failed Step 8/9.** The Step would run, find no page in "writing" or "publishing" and skip, so resume would claim to retry and do nothing. Making it real would mean the pipeline resetting pages, which couples Research to Pages.
- **Allow several Steps of one run at once.** Breaks the one-Step-at-a-time rule that choosing, publishing and settling the run's status rely on.

## Consequences

A run can be `awaiting_choice` after a failed re-publish even if it had been `done` before; the page keeps its earlier published URL.

## Update 2026-11-24

Step 9 (Publish) was removed when the owner trimmed the MVP (see `docs/MEMORY.md`). The decision above now applies to Step 8 alone: it is queued from the Niche choice until its job starts, and a finally failed Step 8 is not retried by resume (the page is `failed` and the User chooses the Niche again). The run status `done` no longer exists, so the consequence about re-publishing no longer applies.
