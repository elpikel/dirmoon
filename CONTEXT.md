# dirmoon

dirmoon turns a plain-language business description into a ranked list of search niches worth going after, and writes a Brief for the one the owner picks: the plan and the text of one page, which the owner hands to whoever builds their site. dirmoon does not build, host or publish the page. It exists to answer "does anyone search for this?" before anything is built.

## Language

The terms below are internal (code, schemas, docs); readers never see them. Screens, emails and the landing page say instead: Niche → "topic" ("need" once named on the screen), Phrase → "search" or "what people type into Google", Rejected Phrases → "Searches I left out", Seed → "starting ideas" / "starting searches", Volume → "how many times a month people type it" ("typed N times a month"), CPC → "what businesses pay Google for one ad click" ("ad click price"), SERP / top 10 → "Google's first page", Score → "rating N out of 10", Competition Verdict → weak / medium / strong plus what it means ("easy to get onto Google's first page", "possible, but not at once", "hard to get onto Google's first page"), Brief → "brief", explained on first use as the plan and the text for one page; only the landing hero, title and meta description keep "niche finder", "monthly search volume" and "keyword competition" for search engines, explained in passing.

### Tenancy

**Account**:
The business that uses dirmoon and owns its data: every Research Run, Niche, Page and Search Console Connection belongs to one Account.
_Avoid_: Customer (as a model name), tenant, organization, workspace

**User**:
A person who signs in to dirmoon with a magic link sent to their email; there are no passwords.

**Membership**:
The link between a User and an Account; a User acts in the Account of their first Membership. No roles yet.

**Sign-up**:
Creating an account from the landing page: an email creates a User, their Account and the Membership, and sends a sign-in link.
_Avoid_: Registration, waitlist

**Search Console Connection**:
An Account's authorised access to Google Search Console, one per Account, used by Step 6 for Existing Site runs.

### Research

**Research Run**:
One pass of the pipeline for one business description, in one Mode, for one Market and optionally one city. Stored in `research_runs`, with the Market's country and language names copied onto the run when it starts.
_Avoid_: Job, search, analysis, project

**Market**:
The country and language a Research Run targets, chosen separately on the new research screen: a country from the Google Ads locations of type Country (its ISO code, the keyword API's location code and its name) and a language the keyword API accepts. Both lists come from DataForSEO, are stored in `market_countries` and `market_languages`, and are fetched again once older than a configured number of days. A first run starts in the United States, in English; later runs start in the Market of the Account's latest run.
_Avoid_: Locale, region

**Mode**:
Which kind of business a Research Run is for: **New Idea** (nothing exists yet) or **Existing Site** (a site with a domain and Search Console data).

**Step**:
One of the eight parts of a Research Run (Seeds, Expansion, Volumes, Filter and Group, Competition, Current Positions, Scoring, Brief), each with its own status and stored output. Steps 1–7 follow each other on their own; Step 8 starts only when the owner chooses a Niche.
_Avoid_: Stage, phase, task

**Step Group**:
One of the four groups the eight Steps are shown in: Phrases (Steps 1–2), Demand (3–4), Competition (5–7), Brief (8).
_Avoid_: Stage

**Awaiting Choice**:
The state of a Research Run whose Niches are scored and which is waiting for the owner to choose one.

**Priority Service**:
One of up to five things the business earns on, given as input to narrow the results.

### Phrases

**Phrase**:
Something people really type into Google, as DataForSEO returns it. Stored in `keywords`, once for all Accounts.
_Avoid_: Keyword (outside table and API names), query, term

**Seed**:
A search phrase guessed by the LLM from the business description, used only as input to Expansion. It becomes a Phrase only if the keyword API returns it.

**Expansion**:
Turning Seeds into the few hundred Phrases people really type, through the keyword API.

**Volume**:
Monthly searches for a Phrase in a location: the country, and the city when given. Shared across Accounts and reused for 30 days.

**CPC**:
What advertisers pay per click on a Phrase; the sign that the traffic is worth money. Shown in USD, as the keyword API returns it.

**Trend**:
A Phrase's Volume over the last 12 months.

**Metrics**:
A Phrase's Volume, CPC and Trend in one location, as last fetched: one row per Phrase and location (`keyword_metrics`), shared across Accounts and reused for 30 days.

**Rejected Phrase**:
A Phrase the filter step dropped from a Research Run, kept with its reason: outside the business, left out of every Niche, or beyond the limit of Phrases analysed.

### Competition

**SERP Snapshot**:
Google's top 10 results for a Phrase in a location on a given date: position, address and title of each. Shared across Accounts and reused for 30 days.

**Page Type**:
The label a Research Run gives a top-10 result: direct competitor, directory, forum, portal or blog. Blogs, forums and directories are the weak types; many of them on the first page make a Niche attractive.

**SERP Assessment**:
One Research Run's judgement of a SERP Snapshot: the Page Type of each result and the Competition Verdict. It depends on the business, so it is never shared.

**Competition Verdict**:
How hard a top 10 is to break into: **weak** (weak Page Types hold more than half), **strong** (direct competitors hold more than half, or five or more places) or **medium**.

**Current Position**:
Where an Existing Site already ranks for a Phrase, from Search Console: its average position over the last 90 days, kept for every Phrase of the run that Search Console knows.

**Quick Win**:
A Phrase whose Current Position is between 8 and 20: the cheapest to push up.

**Price Check**:
What a Niche's direct competitors charge, looked up on demand: the owner starts it for one Niche on the results screen and dirmoon reads up to five Competitor Pages for the Competitor Offers they state. It is not a Step: the run keeps its eight Steps, and the LLM requests it sends add to the run's API Cost.
_Avoid_: Pricing (as a model name)

**Competitor Page**:
One direct competitor's address a Price Check reads: the best-placed address of one domain labelled direct competitor on Google's first page for the Niche's Phrases. It is not a Page (the record of a Brief): dirmoon keeps only what it states. A Price Check notes for each one: prices found, no prices found, or the page could not be opened.

**Competitor Offer**:
One price a Competitor Page states: what it is for, the price exactly as written on the page and a quote from the page that contains it. An offer whose quote is not in the page text, or whose price is not in its quote, is dropped, so no price is ever invented.

### Niches

**Niche**:
A set of Phrases that share an intent, scored and offered to the owner as one thing to go after. Stored in `clusters`.
_Avoid_: Cluster (outside the table name), topic, group, segment

**Score**:
A Niche's 0–10 rating, built from Volume, CPC and the weakness of the competition.

**Worth Going After**:
A Niche with a Score of 4 or more. The results lead with these and fold the rest away.

**Reading**:
The LLM's two-sentence comment on a Niche, written in Step 4: what the people searching it want. Only a Niche has a Reading; a run's view of a top 10 is a SERP Assessment.

**Proposed Niche**:
A Niche Step 4 proposed that the owner has neither chosen nor rejected; every Niche starts proposed.

**Chosen Niche**:
A Niche the owner picked to get a Brief. A Research Run can have several, chosen one at a time.

**Rejected Niche**:
A Niche the owner dropped from the results.

### Output

**Brief**:
The plan and the text of one page about the Chosen Niche, written by Step 8 in the market language for the owner to hand to whoever builds their site: title, H1, URL slug, intro, sections as customer questions with their answers, the Short Answer, the Phrases to cover, and the business details the owner fills in. dirmoon builds no page from it.

**Short Answer**:
The one-sentence direct answer to a Brief's first question, for the top of the page.

**Page**:
The record that holds one Chosen Niche's Brief, with its status while Step 8 writes it (writing, ready, failed). Stored in `pages`, one per Chosen Niche; the owner sees it as a brief. It is not a web page: dirmoon builds, hosts and publishes none.
_Avoid_: Produced page, Landing page (for the record), article, post

**Demo Data**:
Obviously synthetic output from a demo adapter, used in dev while an external service has no credentials; the app shows "TEST DATA" with the names of the services answered this way.

**Placeholder**:
Bracketed upper-case English text (`[PRICE]`, `[PHONE]`, `[BUSINESS NAME]`) marking a value the business owner must supply; the generator never fills it in, and a price, phone, e-mail or address the LLM writes is replaced by one.

**API Cost**:
What a Research Run has itself spent on paid API requests, in USD, shown on the run. Shared market data it reused and requests it had already paid for add nothing.
