# dirmoon

dirmoon turns a plain-language business description into a ranked list of search niches worth going after, then writes a brief and a landing page for the niche you pick. It answers "does anyone search for this?" before anything is built.

Nothing is built yet: this is a fresh Phoenix app. The product spec, the pipeline and the design are in [`docs/design/README.md`](docs/design/README.md).

## Stack

Elixir ~> 1.17, Phoenix 1.8 with LiveView 1.2, Ecto and PostgreSQL, Tailwind v4, Req for HTTP. Oban (the nine pipeline steps) and the external services (an LLM API, DataForSEO, Google Search Console, Pagedock, Plausible) come with the pipeline.

## Setup and run

You need Elixir 1.17 or newer and a local PostgreSQL.

```sh
mix setup        # deps, database, assets
mix phx.server   # http://localhost:4000
```

## Configuration

Dev and test need no environment variables. Production reads the standard Phoenix ones in `config/runtime.exs`: `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`, `PORT` and `PHX_SERVER`.

## Tests and checks

```sh
mix test                        # all tests
mix test path/to/test.exs:LINE  # one test
mix precommit                   # compile (warnings as errors), unlock unused deps, format, credo, test
```

## Docs

- [`docs/design/README.md`](docs/design/README.md): product spec, pipeline, design and open questions
- [`CONTEXT.md`](CONTEXT.md): domain language
- [`ARCHITECTURE.md`](ARCHITECTURE.md): how it's built today
- [`docs/adr/`](docs/adr/): architecture decisions
- [`docs/MEMORY.md`](docs/MEMORY.md): decision log
- [`.claude/README.md`](.claude/README.md): the Claude workflow (`/brainstorm` → `/implement` → commit)
