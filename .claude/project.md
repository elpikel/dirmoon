# 🔧 Project settings for the Claude kit

The kit's commands, agents and skills are generic Elixir/Phoenix. Everything specific to this repo lives here. Edit by hand when a fact changes.

## App

| Setting | Value |
|---|---|
| Name | dirmoon: turns a business description into scored search niches, then writes a brief and a landing page for the chosen niche |
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
| Background jobs | Oban, workers in `lib/dirmoon/workers/`, queue `pipeline`, `testing: :manual` in test |
| Test data | ExMachina factory `Dirmoon.Factory` in `test/support/factory.ex`, `insert(:factory)` |
| External API mocks | Mox: mocks defined in `test/test_helper.exs` (added with each client) |
| API spec | none |
| Web UI | LiveView app under `/app` (`Layouts.app/1`, `DirmoonWeb.UI` components); controller-rendered landing page at `/`; controllers for downloads, CSV export and the Search Console OAuth |

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
| Pipelines (reviewer checks placement) | `:browser` (session, CSRF, secure headers, current scope), `:require_authenticated_user` (signed-in User; every `/app` route and Settings), `:api` (JSON, no auth; not mounted). `live_session :app` mounts `UserAuth :require_authenticated`. |
| API docs for clients | none (no external API clients) |

## Access rules (reviewer fails on any leak)

- Every Research Run, Niche, Page and Search Console Connection belongs to one Account (ADR-0001). A User sees and changes only their Scope's Account's data: context functions take the `Scope` and filter by `scope.account`.
- `account_id` is never cast from params; it comes from the Scope.
- Ids from params (run, niche, page) are resolved through the Scope; a foreign id is "not found" and changes nothing.
- Sign-up never reveals whether an email is already registered.
- Shared market data (`keywords`, `keyword_metrics`, `serp_snapshots`) never holds anything that identifies an Account or its business: no description, domain, run id or Search Console figure (ADR-0002). Per-run choices (kept/rejected, Niche, Page Type labels, current positions) live in per-run tables.
- API keys, the Netlify token and Google OAuth tokens come from runtime config or encrypted columns, and never reach a template, a log line, a CSV or a stored raw response. Google refresh tokens are stored encrypted.
- The Search Console OAuth callback accepts only a `state` issued to the same session.
- A Produced Page contains no invented price, phone, address or e-mail; a missing value is a visible Placeholder.
- Final Phrases come from the keyword API, never from the LLM.
- A paid request a run already stored is never sent again for that run; fresh (< 30 days) Volumes and SERP Snapshots are reused across runs.

## Style overrides

The builder and reviewer enforce the kit's default Elixir style (`.claude/agents/builder.md`). List any default this repo turns off or changes; leave "none" to keep them all.

- none

## Docs

| Doc | Path |
|---|---|
| Domain language | `CONTEXT.md` |
| ADRs | `docs/adr/` |
| Architecture | `ARCHITECTURE.md` |
| Decision log | `docs/MEMORY.md` |
| Product spec and design handover | `docs/design/README.md` (section 9: open questions, ask the owner) |
