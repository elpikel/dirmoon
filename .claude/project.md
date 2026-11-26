# 🔧 Project settings for the Claude kit

The kit's commands, agents and skills are generic Elixir/Phoenix. Everything specific to this repo lives here. Edit by hand when a fact changes.

## App

| Setting | Value |
|---|---|
| Name | dirmoon: turns a business description into scored search niches, then writes a brief (the plan and text of one page) for the chosen niche |
| Stage | ongoing |
| OTP app | `:dirmoon` |
| Context root | `lib/dirmoon/` (`Dirmoon.*`) |
| Web root | `lib/dirmoon_web/` (`DirmoonWeb.*`) |
| Repo | `Dirmoon.Repo` |

## Git and tracking

| Setting | Value |
|---|---|
| Trunk branch | `main` |
| Work on trunk | Allowed: `/implement` runs on the trunk |
| Issue tracker | None: tasks are local, in `.claude/work/<slug>/` |
| Slug | short kebab-case name, e.g. `keyword-expansion` |
| Commit reference | None |

## Databases

| Setting | Value |
|---|---|
| Dev DB (never migrate or roll back) | `dirmoon_dev` |
| Test DB (`mix test` migrates it) | `dirmoon_test` |
| Table prefixes (by owner) | None yet |

## Tooling

Detected from `mix.exs` and `test/`. A tool marked "none" is never run or required by the agents.

| Tool | Value |
|---|---|
| Formatter | `mix format` with Styler (and `Phoenix.LiveView.HTMLFormatter`) |
| Linter | `mix credo --strict`, with ex_slop checks |
| Background jobs | Oban, workers in `lib/dirmoon/workers/`, queues `pipeline` (Steps, Price Checks) and `site_scan` (`ScanSite`, `MatchSitePages`), `testing: :manual` in test |
| Test data | ExMachina factory `Dirmoon.Factory` in `test/support/factory.ex`, `insert(:factory)` |
| External API mocks | Mox: mocks defined in `test/test_helper.exs` (added with each client): `LLMMock`, `DataForSEOMock`, `SearchConsoleMock`, `PageSpeedMock`, `WebPageMock`; each real adapter is tested against `Req.Test` |
| API spec | none |
| Web UI | LiveView app under `/app` (`Layouts.app/1`, `DirmoonWeb.UI` components); controller-rendered landing page at `/`; controllers for the Search Console OAuth only |

## Tests

| Setting | Value |
|---|---|
| Endpoint test case | `DirmoonWeb.ConnCase` |
| Data test case | `Dirmoon.DataCase` |
| Endpoint test file | `test/dirmoon_web/controllers/<controller>/<action>_test.exs`, module `DirmoonWeb.Controllers.<Controller>.<Action>Test` |
| LiveView test file | `test/dirmoon_web/live/<live_view>_test.exs` |
| Module test file | `test/dirmoon/…` mirroring `lib/dirmoon/…` |
| Test-data rules | Every value that must be unique (user emails, Phrase texts, request hashes) comes from an ExMachina sequence in `Dirmoon.Factory` (`insert(:user)`, `params_for(:user)`, `unique_user_email/0`); never a hardcoded address or `System.unique_integer`. Shared market-data rows (`keywords`) get per-test texts unless the test asserts the exact text. Never use the numbers from the reference designs (volumes, CPC, scores) as if they were real data |
| Known flaky | none |

## Web

| Setting | Value |
|---|---|
| Router | `lib/dirmoon_web/router.ex` |
| Path prefixes | `/` (landing, sign-up), `/users/*` (sign-in, settings), `/app` (signed-in app), `/dev` (LiveDashboard and mailbox preview, dev only) |
| Pipelines (reviewer checks placement) | `:browser` (session, CSRF, secure headers, current scope), `:require_authenticated_user` (signed-in User; every `/app` route and Settings), `:redirect_if_user_is_authenticated` (sends a signed-in User from the landing page `GET /` and `POST /sign-up` to `/app`). `live_session :app` mounts `UserAuth :require_authenticated`. |
| API docs for clients | none (no external API clients) |

## Access rules (reviewer fails on any leak)

- Every Research Run, Niche, Page and Search Console Connection belongs to one Account (ADR-0001). A User sees and changes only their Scope's Account's data: context functions take the `Scope` and filter by `scope.account`.
- A Site Scan and its Scanned Pages belong to one Account through their run: they are reached only through a run resolved by the Scope (`SiteScans.report/2`, `get_for_run/2`, `retry/2` take the Scope; `status_of/1`, `matched_pages_by_niche/1` and `niche_comparison/2` take a run already resolved through it). Workers load a scan only by the id in their own job's args, never from params.
- `account_id` is never cast from params; it comes from the Scope.
- Ids from params (run, niche, page) are resolved through the Scope; a foreign id is "not found" and changes nothing.
- Sign-up never reveals whether an email already has a User.
- Shared market data (`keywords`, `keyword_metrics`, `serp_snapshots`) never holds anything that identifies an Account or its business: no description, domain, run id or Search Console figure (ADR-0002). Per-run choices (kept/rejected, Niche, Page Type labels, current positions and their addresses) and everything about the owner's site (`site_scans`, `scanned_pages`) live in per-run tables.
- API keys (OpenAI, DataForSEO, the PageSpeed key) and Google OAuth tokens come from runtime config or encrypted columns, and never reach a template, a log line or a stored raw response. The PageSpeed key travels only in the request address; the stored PageSpeed answer and its error messages have it cut out. Google refresh tokens are stored encrypted.
- Every address the app reads goes through the web page seam (`Dirmoon.WebPage`), whose HTTP adapter passes it and every redirect through `PublicUrl.check/1` (http(s) only, no `localhost` or loopback/private/link-local/shared/unspecified IP literal, at most 2,048 bytes). No code reads an address from a page, a sitemap, robots.txt or a User any other way.
- Text from the web (page text, titles, headings, addresses) goes into an LLM prompt only as JSON data, cut short, with the instruction to ignore anything in it that asks for something. The LLM's page matches may pair only the run's own Scanned Pages with the run's own Niches that were sent: any other page index or Niche id in the answer is dropped.
- The "Read my site" draft's ledger entry is built by the server and kept in the LiveView's state for the domain it was made for; it is never taken from form params.
- The Search Console OAuth callback accepts only a `state` issued to the same session.
- A Brief contains no invented price, phone, address or e-mail; a missing value is a visible Placeholder.
- Final Phrases come from the keyword API, never from the LLM.
- A paid request a run already stored is never sent again for that run; fresh (< 30 days) Volumes and SERP Snapshots are reused across runs.

## Style overrides

The builder and reviewer enforce the kit's default Elixir style (`.claude/agents/builder.md`). List any default this repo turns off or changes; leave "none" to keep them all.

- Code names follow `CONTEXT.md`. A module, schema, field, function, status value or UI label that uses a word the glossary lists under _Avoid_, or a different word for a glossary term, fails review; the builder renames the code (or, when the code's word is the better one, proposes the glossary change in its report) in the same task. Mismatches are never left as "findings for later". Table, column and external-API names may keep the provider's or the handover's word (`keywords`, `keyword_id`, `clusters`).
- Every branch is tested. A builder reports line coverage for the modules it touched and tests every error, fallback and catch-all branch it writes, not only the acceptance criteria; a branch that can't be reached with real data is named in the report with the reason. The reviewer fails a task with an untested branch in its files. `mix precommit` runs the suite with the coverage threshold in `mix.exs`.

## Docs

| Doc | Path |
|---|---|
| Domain language | `CONTEXT.md` |
| ADRs | `docs/adr/` |
| Architecture | `ARCHITECTURE.md` |
| Decision log | `docs/MEMORY.md` |
| Product spec and design handover | `docs/design/README.md` (section 9: open questions, ask the owner) |
