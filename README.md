# dirmoon

dirmoon turns a plain-language business description into a ranked list of search niches worth going after, then writes a brief for the niche you pick: the plan and the text of one page about it (title, headings, sections and the phrases to cover), which you hand to whoever builds your site. It answers "does anyone search for this?" before anything is built.

## Status

v1 is built: the eight-step research pipeline, the four screens (new research, run progress, results, brief) plus the landing page, the runs list and the briefs list, and the site scan with its "Your site" screen. If you already have a site, paste its address: "Read my site" drafts the business description from your home page, and once the research starts dirmoon also scans the site. It reads up to 50 of its pages, asks Google PageSpeed how it does on a phone and asks DataForSEO how many pages Google holds, whether there is a Google Business Profile and how many sites link to it. Then the "Your site" screen explains in plain English what to fix: whether Google can find and read the site, whether each page says what it is about, whether it works on a phone, whether it looks like a real business, and which topics people search for have no page on it. You don't need to connect any Google account. On the results screen you can check what a niche's direct competitors charge: dirmoon opens up to five of their pages from Google's first page and lists the prices they publish, each linked to the page it came from. For an existing site it also compares your page for that topic with theirs. dirmoon does not build, host or publish the page: the MVP cut publishing to Netlify and then the page build and its HTML download, and kept the Brief. The product spec and design are in [`docs/design/README.md`](docs/design/README.md).

Not exercised yet:

- The LLM is OpenAI (`Dirmoon.LLM.OpenAI`). Without `OPENAI_API_KEY` dev uses demo data; in production the LLM steps fail with "No OpenAI API key".
- The DataForSEO, Google Search Console and Google PageSpeed clients were built from their documentation and have never been run against the live services. That includes the DataForSEO requests the site scan uses (ranked phrases, the `site:` page count, Business Profile, linking sites).
- The competitor price check and the site scan read real web pages in dev and prod (they need no credentials); they have only been tested against stubs.

## Stack

Elixir ~> 1.17, Phoenix 1.8 with LiveView 1.2, Ecto and PostgreSQL, Tailwind v4, Req for HTTP. Oban runs the eight pipeline steps on the `pipeline` queue and the site scan on the `site_scan` queue; LazyHTML parses the web pages dirmoon reads. External services: OpenAI (the LLM), DataForSEO, Google PageSpeed Insights and, optionally, Google Search Console. The interface is in English; Seeds, Phrases and Briefs are in the run's market language. A run can target any country DataForSEO's keyword data covers, in any language it accepts: both lists are fetched from DataForSEO (free requests) and cached in the database. Tests use Mox and ExMachina; checks use Styler, Credo and ex_slop.

## Setup and run

You need Elixir 1.17 or newer and a local PostgreSQL.

```sh
mix setup        # deps, database, assets
mix phx.server   # http://localhost:4000
```

Sign up on the landing page. The sign-in link arrives in the dev mailbox at [`/dev/mailbox`](http://localhost:4000/dev/mailbox).

## Configuration

Dev runs with no environment variables: demo adapters stand in for OpenAI and DataForSEO (Search Console and PageSpeed have none and are simply not configured; and demo data never describes your real site, so the site scan's outside checks, the page matching and "Read my site" say they were not done), and the app shows a "TEST DATA" banner naming the services still on demo data. Setting a service's variables switches that service to its real client, in dev too. The app does not read a `.env` file: export the variables in the shell that starts the server (a variable that is set but not exported never reaches it). Tests ignore these variables.

| Variable | Turns on | Without it |
|---|---|---|
| `OPENAI_API_KEY` | Real Seeds, filtering and grouping, SERP labels, Briefs, competitor prices, "Read my site" drafts and the matching of a site's pages to its niches from OpenAI | Dev: demo answers; no draft and no page matching. Prod: the step fails with "No OpenAI API key"; the site scan notes the matching as not done |
| `OPENAI_MODEL` | Another OpenAI model than `gpt-6.2-sol`; it must have prices in `config/config.exs` | `gpt-6.2-sol` |
| `DATAFORSEO_LOGIN` + `DATAFORSEO_PASSWORD` (both) | Real phrase ideas, volumes and SERP top 10 from DataForSEO, the full lists of countries and languages a run can target, where an existing site ranks (Step 6), and the site scan's indexed page count, Business Profile and linking sites | Dev: demo data, and only the United States, the United Kingdom and Poland with English and Polish; no demo data about your site (Step 6 uses only the run's own first pages, the scan notes those checks as not done). Prod: the step fails with "No DataForSEO credentials", and with no lists stored the new research screen says DataForSEO isn't configured and can't start a run |
| `GOOGLE_CLIENT_ID` + `GOOGLE_CLIENT_SECRET` (both) | Connecting Google Search Console (optional, Existing Site runs): Step 6 then uses Google's own 90-day positions when the connection can read the site | Dev and prod: the "Connect Search Console" link still shows and connecting reports "Search Console is not configured"; Step 6 (where your site shows up) uses DataForSEO instead |
| `PAGESPEED_API_KEY` | The site scan's phone speed and phone-usability check of the home page, with Google PageSpeed Insights (dirmoon's own Google Cloud API key; `.env.example` says how to create one) | The scan notes that phone speed wasn't checked |
| `DATABASE_URL`, `SECRET_KEY_BASE` | Prod database and cookie signing (required) | Prod does not start |
| `PHX_HOST`, `POOL_SIZE` | Prod host, database pool size | `example.com`, `10` |
| `PORT` | HTTP port, read in every environment | `4000` |
| `PHX_SERVER` | Starts the web server in a release | A release starts without serving HTTP |
| `ECTO_IPV6`, `DNS_CLUSTER_QUERY` | IPv6 database socket, DNS clustering | IPv4, no clustering |

Step by step for the Google variables (`GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `PAGESPEED_API_KEY`): [`docs/google-setup.md`](docs/google-setup.md).

Google redirect URI to add to the Google Cloud OAuth client: `https://<PHX_HOST>/app/search-console/callback` (dev with real credentials: `http://localhost:4000/app/search-console/callback`).

**LLM:** `Dirmoon.LLM.OpenAI` calls the Responses API with strict Structured Outputs. A call's cost is its token usage times the per-model prices in `config :dirmoon, Dirmoon.LLM.OpenAI` (`prices`, USD per million tokens); a model with no prices there is refused, so add its prices before setting `OPENAI_MODEL` to it.

**Mailer:** production sends sign-in links through Brevo and does not start without `BREVO_API_KEY`. `MAIL_FROM` is the sender address (default `no-reply@dirmoon.com`); it must be a sender verified in Brevo. Dev keeps the local mailbox at `/dev/mailbox`.

**Tunables** in `config/config.exs`:

- `serp_phrase_limit`: how many of the top kept phrases get a SERP check.
- `serp_max_age_days`: how old a stored SERP snapshot may be and still be reused.
- `market_lists_max_age_days`: how old the stored lists of countries and languages may get before they are fetched again (30). A failed fetch keeps the stored lists.
- `grouping_phrase_limit`: how many phrases go to the LLM for filtering and grouping.
- `scoring_weights`: weights of volume, CPC and competitor weakness in the niche score.
- `cost_estimates`: per-request USD prices behind the cost estimate on the new research screen.
- `price_check_page_limit`: how many competitor pages one price check reads (5).
- `site_scan_page_limit`: how many pages one site scan reads (50).
- `site_scan_stale_after_minutes`: how long a scan may go without storing anything before the "Your site" screen offers to run it again (15).
- `ranked_phrases_limit`: how many of the phrases a site ranks for Step 6 buys from DataForSEO (1000).

## Deploy

The `Dockerfile` builds a release image. On start the container runs pending migrations, then serves plain HTTP on port 4000; HTTPS is the proxy's job (the app redirects to HTTPS from the proxy's `X-Forwarded-Proto` header). On Coolify: add the GitHub repository as an application with the Dockerfile build pack and port 4000, add a PostgreSQL database, set the domain, and set these variables:

- `DATABASE_URL`: the database's internal URL, as Coolify shows it.
- `SECRET_KEY_BASE`: the output of `mix phx.gen.secret`.
- `PHX_HOST`: the domain, without `https://` (default `dirmoon.com`).
- `BREVO_API_KEY` and, to change the sender, `MAIL_FROM`: see Mailer above.
- The service keys from `.env.example`, without `export`.

After the first deploy: make `www.dirmoon.com` redirect to `dirmoon.com` in Coolify (two addresses serving the same page count against the site), add the domain to Google Search Console and submit `https://dirmoon.com/sitemap.xml`. `priv/static/robots.txt` and `priv/static/sitemap.xml` hold the domain literally; change them if it changes.

## Running a real run

1. Set `OPENAI_API_KEY`, `DATAFORSEO_LOGIN` and `DATAFORSEO_PASSWORD`; for an existing site also `PAGESPEED_API_KEY` (and `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` if you want Search Console's figures).
2. Restart the server.
3. Start a research from the new research screen. For an existing site, type its address and press "Read my site" to draft the description, or write it yourself.

Each run shows its API cost so far, including the "Read my site" draft that started it. Volumes and SERP snapshots fetched in the last 30 days, by any run, are reused instead of bought again. OpenAI or DataForSEO with missing variables keeps answering with demo data in dev, so a run with only one of them set mixes real and demo output. Search Console and PageSpeed have no demo data: without their variables they are simply not configured.

The cost estimate on the new research screen adds, for an existing site, Step 6's ranked phrases (at the full `ranked_phrases_limit`) and the scan's indexed page count, Business Profile and linking sites requests. It leaves out the "Read my site" draft and the page matching (the LLM allowance is 0 until a real run shows the LLM share) and price checks, which you start yourself.

DataForSEO list prices as researched in November 2026. They are unverified estimates; the `cost` field in each API response is what a run records:

| Request | Price |
|---|---|
| Google Ads Live (keywords for keywords, search volume) | $0.09 per request |
| Google Organic SERP Live, top 10 | $0.002 per SERP |
| Google Organic SERP Live with `site:` (the indexed page count) | five times a SERP, $0.01 |
| Labs ranked keywords (where a site ranks) | $0.012 per request plus $0.00012 per phrase returned |
| Business Data, Google My Business Info Live | $0.0054 per request |
| Backlinks (linking sites, all domains of one request together) | $0.024 per request plus $0.000036 per row (rows per domain not confirmed) |
| Minimum top-up | $50 |

Google PageSpeed Insights requests are recorded at no cost. Its price and quota are not stated on the Google pages read so far (unverified); a refused request because of the quota shows on the "Your site" screen as a speed check not done.

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
