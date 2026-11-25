# dirmoon

dirmoon turns a plain-language business description into a ranked list of search niches worth going after, then writes a brief for the niche you pick: the plan and the text of one page about it (title, headings, sections and the phrases to cover), which you hand to whoever builds your site. It answers "does anyone search for this?" before anything is built.

## Status

v1 is built: the eight-step research pipeline, the four screens (new research, run progress, results, brief) plus the landing page, the runs list and the briefs list. On the results screen you can check what a niche's direct competitors charge: dirmoon opens up to five of their pages from Google's first page and lists the prices they publish, each linked to the page it came from. dirmoon does not build, host or publish the page: the MVP cut publishing to Netlify and then the page build and its HTML download, and kept the Brief. The product spec and design are in [`docs/design/README.md`](docs/design/README.md).

Not exercised yet:

- The LLM is OpenAI (`Dirmoon.LLM.OpenAI`). Without `OPENAI_API_KEY` dev uses demo data; in production the LLM steps fail with "No OpenAI API key".
- The DataForSEO and Google Search Console clients were built from their documentation and have never been run against the live services.
- The competitor price check reads real competitor pages in dev and prod (it needs no credentials); it has only been tested against stubs.

## Stack

Elixir ~> 1.17, Phoenix 1.8 with LiveView 1.2, Ecto and PostgreSQL, Tailwind v4, Req for HTTP. Oban runs the eight pipeline steps on the `pipeline` queue. External services: OpenAI (the LLM), DataForSEO and Google Search Console. The interface is in English; Seeds, Phrases and Briefs are in the run's market language. Tests use Mox and ExMachina; checks use Styler, Credo and ex_slop.

## Setup and run

You need Elixir 1.17 or newer and a local PostgreSQL.

```sh
mix setup        # deps, database, assets
mix phx.server   # http://localhost:4000
```

Sign up on the landing page. The sign-in link arrives in the dev mailbox at [`/dev/mailbox`](http://localhost:4000/dev/mailbox).

## Configuration

Dev runs with no environment variables: demo adapters stand in for every external service, and the app shows a "TEST DATA" banner naming the services still on demo data. Setting a service's variables switches that service to its real client, in dev too. The app does not read a `.env` file: export the variables in the shell that starts the server (a variable that is set but not exported never reaches it). Tests ignore these variables.

| Variable | Turns on | Without it |
|---|---|---|
| `OPENAI_API_KEY` | Real Seeds, filtering and grouping, SERP labels, Briefs and competitor prices from OpenAI | Dev: demo answers. Prod: the step fails with "No OpenAI API key" |
| `OPENAI_MODEL` | Another OpenAI model than `gpt-6.2-sol`; it must have prices in `config/config.exs` | `gpt-6.2-sol` |
| `DATAFORSEO_LOGIN` + `DATAFORSEO_PASSWORD` (both) | Real phrase ideas, volumes and SERP top 10 from DataForSEO | Dev: demo data. Prod: the step fails with "No DataForSEO credentials" |
| `GOOGLE_CLIENT_ID` + `GOOGLE_CLIENT_SECRET` (both) | Connecting Google Search Console, for Existing Site runs | Dev: demo connection. Prod: Step 6 (current positions) is skipped |
| `DATABASE_URL`, `SECRET_KEY_BASE` | Prod database and cookie signing (required) | Prod does not start |
| `PHX_HOST`, `POOL_SIZE` | Prod host, database pool size | `example.com`, `10` |
| `PORT` | HTTP port, read in every environment | `4000` |
| `PHX_SERVER` | Starts the web server in a release | A release starts without serving HTTP |
| `ECTO_IPV6`, `DNS_CLUSTER_QUERY` | IPv6 database socket, DNS clustering | IPv4, no clustering |

Google redirect URI to add to the Google Cloud OAuth client: `https://<PHX_HOST>/app/search-console/callback` (dev with real credentials: `http://localhost:4000/app/search-console/callback`).

**LLM:** `Dirmoon.LLM.OpenAI` calls the Responses API with strict Structured Outputs. A call's cost is its token usage times the per-model prices in `config :dirmoon, Dirmoon.LLM.OpenAI` (`prices`, USD per million tokens); a model with no prices there is refused, so add its prices before setting `OPENAI_MODEL` to it.

**Mailer:** production still uses the local Swoosh adapter. Configure a real one in `config/runtime.exs` (commented example there) before deploying, or sign-in links won't be delivered.

**Tunables** in `config/config.exs`:

- `serp_phrase_limit`: how many of the top kept phrases get a SERP check.
- `serp_max_age_days`: how old a stored SERP snapshot may be and still be reused.
- `grouping_phrase_limit`: how many phrases go to the LLM for filtering and grouping.
- `scoring_weights`: weights of volume, CPC and competitor weakness in the niche score.
- `cost_estimates`: per-request USD prices behind the cost estimate on the new research screen.
- `price_check_page_limit`: how many competitor pages one price check reads (5).

## Running a real run

1. Set `OPENAI_API_KEY`, `DATAFORSEO_LOGIN` and `DATAFORSEO_PASSWORD` (and `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` if you need Search Console).
2. Restart the server.
3. Start a research from the new research screen.

Each run shows its API cost so far. Volumes and SERP snapshots fetched in the last 30 days, by any run, are reused instead of bought again. A service whose variables are missing keeps answering with demo data in dev, so a run with only some of them set mixes real and demo output.

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
