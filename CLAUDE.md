# dirmoon

@AGENTS.md

Turns a plain-language business description into a ranked list of search niches worth going after, then writes a brief and a landing page for the chosen niche. Overview: `README.md`. Product spec and design handover: `docs/design/README.md`. Domain language: `CONTEXT.md`. Architecture: `ARCHITECTURE.md`.

## Commands

- `mix setup` - install deps, create and migrate the DB, build assets
- `mix phx.server` - run the app at http://localhost:4000
- `mix test` - run all tests
- `mix test path/to/test.exs:LINE` - run one test
- `mix precommit` - compile with warnings as errors, unlock unused deps, format, credo, test with coverage (fails below the `test_coverage` threshold in `mix.exs`)

## Product rules

These come from `docs/design/README.md`; read it before building a pipeline step or a screen.

- **Open questions are the owner's.** Section 9 of the handover lists what isn't decided (LLM provider, scoring weights, Pagedock deploy interface, the name itself…). Ask, don't guess.
- **The LLM never invents final phrases.** It writes Seeds and filters, groups and writes content; Phrases come from the keyword API.
- **Never re-buy data.** Every step's output and every raw API response is stored (`jsonb` next to the parsed rows); resuming a run or changing a prompt reuses what's stored.
- **Every run shows its API cost.**
- **Pages contain no invented price, phone, address or factual claim.** A missing value stays a visible `[PLACEHOLDER]`.
- **Numbers in the reference designs are invented.** Never copy them into seeds, fixtures presented as real, or copy.
- **UI:** interface copy is Polish; colours only from `assets/css/tokens.css` (handover tokens plus the app surface tokens); every screen works at 390 px wide.
- **v1 has one user, the owner:** no accounts, billing, onboarding or multi-tenancy.

## Agent skills

### Work tracking

No issue tracker: tasks are local, with plans and working docs in `.claude/work/<slug>/` (git-ignored). Flow: `/brainstorm` → review → `/implement` (uncommitted, may run on `main`) → review → "yes, commit". See `.claude/README.md`; repo settings in `.claude/project.md`.

### Domain docs

Single-context layout: one `CONTEXT.md` + `docs/adr/` at the repo root.
