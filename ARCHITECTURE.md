# Architecture

How dirmoon is built today. Planned work lives in `docs/design/README.md` (the product spec and build order), `.claude/work/` plans and `docs/adr/`, not here.

## Overview

A fresh `mix phx.new` app: no domain code, no migrations, one generated home page. The pipeline, the data model and the four screens in the spec aren't built yet.

## Stack

- Elixir ~> 1.17, Phoenix 1.8, Phoenix LiveView 1.2, Bandit
- Ecto with PostgreSQL (`Dirmoon.Repo`)
- Tailwind v4 and esbuild (daisyUI is vendored by the generator; new screens don't use it)
- Swoosh for email, Req for HTTP
- Styler, Credo (`--strict`) and ex_slop, all run by `mix precommit`

## Web

| Scope | Pipeline | Serves |
|---|---|---|
| `/` | `:browser` | Generated home page (`PageController.home/2`) |
| `/dev` | `:browser` (dev only) | LiveDashboard, Swoosh mailbox |

No authentication.

## Background work

None yet.

## Data

No tables yet.

## External services

None yet.

## Layout

| Path | What goes there |
|---|---|
| `lib/dirmoon/` | Contexts (`Dirmoon.*`): domain logic, Ecto schemas, queries |
| `lib/dirmoon_web/` | Web layer (`DirmoonWeb.*`): router, controllers, components (`components/core_components.ex`, `components/layouts.ex`) |
| `priv/repo/migrations/` | Migrations (generate with `mix ecto.gen.migration`) |
| `test/dirmoon/` | Context tests, mirroring `lib/dirmoon/` |
| `test/dirmoon_web/` | Controller tests in `controllers/`, LiveView tests in `live/` |
| `test/support/` | `ConnCase`, `DataCase` |
| `docs/design/` | Product spec and design handover |

## Where new code goes

- A new domain area gets its own context module under `lib/dirmoon/`, owning its schemas and tables.
- Each pipeline Step is an Oban worker under `lib/dirmoon/workers/` (once Oban is added) that calls a context and stores its output, so a Research Run can resume without calling a paid API twice.
- Each external service (LLM, DataForSEO, Search Console, Pagedock) gets a client module built on Req, behind a behaviour so tests can replace it.
- UI is LiveView, under `lib/dirmoon_web/live/`, inside `Layouts.app/1`, styled with the design tokens.
