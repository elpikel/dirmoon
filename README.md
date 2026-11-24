# dirmoon

dirmoon turns a plain-language business description into a ranked list of search niches worth going after, then writes a brief and a landing page for the niche you pick. It answers "does anyone search for this?" before anything is built.

## Status

v1 is built: the nine-step research pipeline, the four screens (new research, run progress, results, page) plus the landing page, the runs list and the pages list. The product spec and design are in [`docs/design/README.md`](docs/design/README.md).

Not exercised yet:

- No LLM provider is wired. Dev uses demo data; in production the LLM steps fail with "Nie wybrano dostawcy LLM".
- The DataForSEO, Google Search Console and Netlify clients were built from their documentation and have never been run against the live services.

## Stack

Elixir ~> 1.17, Phoenix 1.8 with LiveView 1.2, Ecto and PostgreSQL, Tailwind v4, Req for HTTP. Oban runs the nine pipeline steps on the `pipeline` queue. External services: an LLM (provider not chosen), DataForSEO, Google Search Console and Netlify. Tests use Mox and ExMachina; checks use Styler, Credo and ex_slop.

## Setup and run

You need Elixir 1.17 or newer and a local PostgreSQL.

```sh
mix setup        # deps, database, assets
mix phx.server   # http://localhost:4000
```

Sign up on the landing page. The sign-in link arrives in the dev mailbox at [`/dev/mailbox`](http://localhost:4000/dev/mailbox).

## Configuration

Dev runs with no environment variables: demo adapters stand in for every external service, and the app shows a "DANE TESTOWE" banner (`config :dirmoon, :demo_data`, `true` in dev). Setting a service's variables switches that service to its real client, in dev too. Tests ignore these variables.

| Variable | Turns on | Without it |
|---|---|---|
| `DATAFORSEO_LOGIN` + `DATAFORSEO_PASSWORD` (both) | Real phrase ideas, volumes and SERP top 10 from DataForSEO | Dev: demo data. Prod: the step fails with "Brak danych logowania DataForSEO" |
| `NETLIFY_TOKEN` | Publishing pages to Netlify | Dev: demo publish. Prod: publishing fails with "Brak tokenu Netlify". Downloading the page still works |
| `GOOGLE_CLIENT_ID` + `GOOGLE_CLIENT_SECRET` (both) | Connecting Google Search Console, for Existing Site runs | Dev: demo connection. Prod: Step 6 (current positions) is skipped |
| `DATABASE_URL`, `SECRET_KEY_BASE` | Prod database and cookie signing (required) | Prod does not start |
| `PHX_HOST`, `POOL_SIZE` | Prod host, database pool size | `example.com`, `10` |
| `PORT` | HTTP port, read in every environment | `4000` |
| `PHX_SERVER` | Starts the web server in a release | A release starts without serving HTTP |
| `ECTO_IPV6`, `DNS_CLUSTER_QUERY` | IPv6 database socket, DNS clustering | IPv4, no clustering |

Google redirect URI to add to the Google Cloud OAuth client: `https://<PHX_HOST>/app/search-console/callback` (dev with real credentials: `http://localhost:4000/app/search-console/callback`).

**LLM:** no environment variable yet, because the provider is undecided. A real adapter implements the `Dirmoon.LLM` behaviour (`structured/1`) and is selected with `config :dirmoon, :llm_adapter`.

**Mailer:** production still uses the local Swoosh adapter. Configure a real one in `config/runtime.exs` (commented example there) before deploying, or sign-in links won't be delivered.

**Tunables** in `config/config.exs`:

- `serp_phrase_limit`: how many of the top kept phrases get a SERP check.
- `serp_max_age_days`: how old a stored SERP snapshot may be and still be reused.
- `grouping_phrase_limit`: how many phrases go to the LLM for filtering and grouping.
- `scoring_weights`: weights of volume, CPC and competitor weakness in the niche score.
- `cost_estimates`: per-request USD prices behind the cost estimate on the new research screen.

## Running a real run

1. Set `DATAFORSEO_LOGIN` and `DATAFORSEO_PASSWORD` (and `NETLIFY_TOKEN`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` if you need publishing or Search Console).
2. Restart the server.
3. Start a research from the new research screen.

Each run shows its API cost so far. Volumes and SERP snapshots fetched in the last 30 days, by any run, are reused instead of bought again. Until an LLM adapter exists, the LLM steps still return demo output in dev.

DataForSEO list prices as researched in November 2026. They are unverified estimates; the `cost` field in each API response is what a run records:

| Request | Price |
|---|---|
| Google Ads Live (keywords for keywords, search volume) | $0.09 per request |
| Google Organic SERP Live, top 10 | $0.002 per SERP |
| Minimum top-up | $50 |

## Tests and checks

```sh
mix test                        # all tests
mix test path/to/test.exs:LINE  # one test
mix precommit                   # compile (warnings as errors), unlock unused deps, format, credo, test --cover (threshold in mix.exs)
```

Tests never hit the network: Mox stands in for the external clients and `Req.Test` for their HTTP.

## Docs

- [`docs/design/README.md`](docs/design/README.md): product spec, pipeline, design and open questions
- [`CONTEXT.md`](CONTEXT.md): domain language
- [`ARCHITECTURE.md`](ARCHITECTURE.md): how it's built today
- [`docs/adr/`](docs/adr/): architecture decisions
  - [`0001-accounts-with-open-sign-up.md`](docs/adr/0001-accounts-with-open-sign-up.md)
  - [`0002-market-data-is-shared-across-accounts.md`](docs/adr/0002-market-data-is-shared-across-accounts.md)
- [`docs/MEMORY.md`](docs/MEMORY.md): decision log
- [`.claude/README.md`](.claude/README.md): the Claude workflow (`/brainstorm` → `/implement` → commit)
