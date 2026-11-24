# 🔧 Project settings for the Claude kit

The kit's commands, agents and skills are generic Elixir/Phoenix. Everything specific to this repo lives here. Edit by hand when a fact changes.

## App

| Setting | Value |
|---|---|
| Name | dirmoon: turns a business description into scored search niches, then writes a brief and a landing page for the chosen niche |
| Stage | new (no domain code yet) |
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
| Background jobs | none (Oban planned for the nine pipeline steps; workers go in `lib/dirmoon/workers/` once added) |
| Test data | none yet |
| External API mocks | none (the LLM, DataForSEO, Search Console and Pagedock clients will each need a seam once added) |
| API spec | none |
| Web UI | controller-rendered `phx.new` home page at `/`; the four screens will be LiveView |

## Tests

| Setting | Value |
|---|---|
| Endpoint test case | `DirmoonWeb.ConnCase` |
| Data test case | `Dirmoon.DataCase` |
| Endpoint test file | `test/dirmoon_web/controllers/<controller>/<action>_test.exs`, module `DirmoonWeb.Controllers.<Controller>.<Action>Test` |
| LiveView test file | `test/dirmoon_web/live/<live_view>_test.exs` |
| Module test file | `test/dirmoon/…` mirroring `lib/dirmoon/…` |
| Test-data rules | Never use the numbers from the reference designs (volumes, CPC, scores) as if they were real data |
| Known flaky | none |

## Web

| Setting | Value |
|---|---|
| Router | `lib/dirmoon_web/router.ex` |
| Path prefixes | `/` (browser), `/dev` (LiveDashboard and mailbox preview, dev only) |
| Pipelines (reviewer checks placement) | `:browser` (session, CSRF, secure headers), `:api` (JSON, no auth; not mounted) |
| API docs for clients | none (no external API clients) |

## Access rules (reviewer fails on any leak)

None yet: no authentication. Version 1 has one user (the owner), so there are no accounts or tenancy; the app is to sit behind a single shared password or network-level protection, which isn't built yet.

Rules the reviewer does enforce on the pipeline and the produced pages:

- API keys and OAuth tokens (LLM, DataForSEO, Search Console, Pagedock) come from runtime config, and never reach a template, a log line or a stored raw response.
- A produced page contains no invented price, phone number, address or factual claim; a missing value is a visible `[PLACEHOLDER]`.
- Final Phrases come from the keyword API, never from the LLM.
- A step that already has stored output doesn't call a paid API again.

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
