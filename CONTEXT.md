# dirmoon

dirmoon turns a plain-language business description into a ranked list of search niches worth going after, and writes a Brief for the one the owner picks: the plan and the text of one page, which the owner hands to whoever builds their site. dirmoon does not build, host or publish the page. It exists to answer "does anyone search for this?" before anything is built.

## Language

The terms below are internal (code, schemas, docs); readers never see them. Screens, emails and the landing page say instead: Niche → "topic" ("need" once named on the screen), Phrase → "search" or "what people type into Google", Rejected Phrases → "Searches I left out", Seed → "starting ideas" / "starting searches", Volume → "how many times a month people type it" ("typed N times a month"), CPC → "what businesses pay Google for one ad click" ("ad click price"), SERP / top 10 → "Google's first page", Score → "rating N out of 10", Competition Verdict → weak / medium / strong plus what it means ("easy to get onto Google's first page", "possible, but not at once", "hard to get onto Google's first page"), Brief → "brief", explained on first use as the plan and the text for one page; only the landing hero, title and meta description keep "niche finder", "monthly search volume" and "keyword competition" for search engines, explained in passing.

### Tenancy

**Account**:
The business that uses dirmoon and owns its data: every Research Run, Niche, Page and Search Console Connection belongs to one Account, and a Site Scan belongs to it through its run.
_Avoid_: Customer (as a model name), tenant, organization, workspace

**User**:
A person who signs in to dirmoon with a magic link sent to their email; there are no passwords.

**Membership**:
The link between a User and an Account; a User acts in the Account of their first Membership. No roles yet.

**Sign-up**:
Creating an account from the landing page: an email creates a User, their Account and the Membership, and sends a sign-in link.
_Avoid_: Registration, waitlist

**Search Console Connection**:
An Account's authorised access to Google Search Console, one per Account. Optional: Step 6 uses it for an Existing Site run when it can read the run's domain and has queries for it, because Google's own figures are exact; otherwise Step 6 uses the keyword API. It answers only for a site the connected Google account has access to.

### Research

**Research Run**:
One pass of the pipeline for one business description, in one Mode, for one Market and optionally one city. Stored in `research_runs`, with the Market's country and language names copied onto the run when it starts.
_Avoid_: Job, search, analysis, project

**Market**:
The country and language a Research Run targets, chosen separately on the new research screen: a country from the Google Ads locations of type Country (its ISO code, the keyword API's location code and its name) and a language the keyword API accepts. Both lists come from DataForSEO, are stored in `market_countries` and `market_languages`, and are fetched again once older than a configured number of days. A first run starts in the United States, in English; later runs start in the Market of the Account's latest run.
_Avoid_: Locale, region

**Mode**:
Which kind of business a Research Run is for: **New Idea** (nothing exists yet) or **Existing Site** (a site with a domain, which also gets a Site Scan).

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
Where an Existing Site already ranks for a Phrase, with the address that ranks when the source gives one. From Search Console when the Account's Connection can read the domain and has queries for it (the average position over the last 90 days, no address); otherwise from the keyword API's ranked phrases for the domain in the run's country, and, for the Phrases those don't place, the run's own SERP Snapshots. When the keyword API can't give ranked phrases, only the SERP Snapshots are used and Step 6 says so. A result counts as the site when its host is the run's domain or `www.` and the domain. Kept per run, for kept and rejected Phrases.

**Quick Win**:
A Phrase whose Current Position is between 8 and 20: the cheapest to push up.

**Price Check**:
What a Niche's direct competitors charge, looked up on demand: the owner starts it for one Niche on the results screen and dirmoon reads up to five Competitor Pages for the Competitor Offers they state. It is not a Step: the run keeps its eight Steps, and the LLM requests it sends add to the run's API Cost.
_Avoid_: Pricing (as a model name)

**Competitor Page**:
One direct competitor's address a Price Check reads: the best-placed address of one domain labelled direct competitor on Google's first page for the Niche's Phrases. It is not a Page (the record of a Brief): dirmoon keeps only what it states. A Price Check notes for each one: prices found, no prices found, or the page could not be opened.

**Competitor Offer**:
One price a Competitor Page states: what it is for, the price exactly as written on the page and a quote from the page that contains it. An offer whose quote is not in the page text, or whose price is not in its quote, is dropped, so no price is ever invented.

### Site Scan

**Site Scan**:
Reading an Existing Site's own pages and checking them, one per Research Run, started with the run. It reads up to the page limit (50) of the site's own pages within its robots.txt, checks the links it found, asks outside services what they say about the site (phone speed, Google's rough count of its indexed pages, its Google Business Profile, its Linking Sites), and, once Step 4 has made the Niches, matches its pages to them. It is not a Step: it runs beside Steps 1–7 with its own status (scanning, done, failed), so a site that can't be read never fails the research; a failed scan, or one that stopped storing anything, can be run again and keeps the pages already read. It stores facts, never conclusions; Findings are worked out from them when shown.
_Avoid_: Audit

**Scanned Page**:
One page of the site a Site Scan read, in read order: its address, the HTTP status it answered with, its Page Facts and the Niche it was matched to, if any. A page whose read ended on another host has no Page Facts; a page that gave no answer keeps only why. Stored in `scanned_pages`, at most the page limit per scan. It is not a Page (the record of a Brief) and not a Competitor Page.

**Page Facts**:
What dirmoon reads off one web page without judging it: title, description, canonical address, robots meta, headings, amount of text, images with and without descriptions, links, declared language, phone set-up (viewport), structured data and the business name it gives, phone and e-mail links, and ways to act. Kept in full for a Scanned Page; a Competitor Page keeps only the few that compare one page with another. The HTML itself is never kept.

**Finding**:
One thing a Site Scan tells the owner, worked out from the stored facts, the run's Niches and its Current Positions: which of five questions it answers (can Google find the site, what each page says, does the site cover what people search for, does it work for a visitor, does it show a real business), the check, its level (problem, warning, not checked, good), the pages concerned and the figures behind it. A Finding says only what was measured; a check that could not be made is "not checked" with its reason (the service isn't connected, Demo Data, the request failed or was refused, the speed test's quota or it couldn't open the page, no business name on the site, no data for the site, the page limit was reached, the matching hasn't run yet). Never stored and never written by the LLM.
_Avoid_: Issue

**Linking Sites**:
How many other sites link to a site, as DataForSEO's own link index knows: an approximate count, never the whole web. Asked for the Existing Site's domain by its Site Scan and for each Competitor Page's domain by a Price Check, so the owner can compare them; no data is unknown, never zero.

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
Obviously synthetic output from a demo adapter (the LLM and the keyword API only), used in dev while that service has no credentials; the app shows "TEST DATA" with the names of the services answered this way. Demo Data never says anything about the owner's real site or business: the ranked phrases, indexed page count, Business Profile, Linking Sites, the matching of pages to Niches and the drafted description have no demo answer and show as not done.

**Placeholder**:
Bracketed upper-case English text (`[PRICE]`, `[PHONE]`, `[BUSINESS NAME]`) marking a value the business owner must supply; the generator never fills it in, and a price, phone, e-mail or address the LLM writes is replaced by one.

**API Cost**:
What a Research Run has itself spent on paid API requests, in USD, shown on the run. Shared market data it reused and requests it had already paid for add nothing.

### Paying

Screens say "research" for a Research Run, "plan" for the Subscription and "researches left" for what the Allowances still hold; "Allowance" and "Unpaid Access" never appear on a screen.

**Single Research**:
One research bought with a one-off payment at the configured price, to try dirmoon. It does not renew and does not expire, and can be bought again at any time, by a subscriber too.

**Subscription**:
An Account's monthly plan, paid through Stripe at the configured monthly price for the configured number of researches a month, at most one per Account. dirmoon keeps what Stripe's events last reported: its Stripe status, the dates of the paid month and, once a cancellation is scheduled, when it ends. It runs until Stripe reports it cancelled or expired, and while it runs the Account can't start a second one. Stripe is where it is started, changed and cancelled.
_Avoid_: Tier, package

**Allowance**:
A number of researches an Account has paid for, one row per payment Stripe confirmed: the configured number of researches a month for a paid Subscription month, valid until that month ends (unused researches don't carry over), or 1 for a Single Research, with no end. Starting a Research Run spends one research from an Allowance, the month's first, and the run keeps which. An Account with nothing left keeps its results and can start nothing new.
_Avoid_: Credit, balance

**Research Cap**:
How many Briefs and how many Price Checks one Research Run includes (configured). Applies to every run, an Unpaid Access Account's too. A failed Brief doesn't count; a failed Price Check does, but running it again is always allowed.

**Unpaid Access**:
A mark on an Account that lets it start Research Runs without an Allowance: the owner's own Account, a tester's. Only the owner sets it, from the server console; in dev every Account signed up after the paying change gets it.
_Avoid_: Free plan, trial

**Stripe Event**:
One webhook event Stripe sent, stored as received on its first delivery and marked processed once dirmoon has acted on it. It is the only way dirmoon learns of a payment or a Subscription change. An event stored but not processed (it couldn't be read) is tried again on Stripe's next delivery; one already processed changes nothing when it comes again.
