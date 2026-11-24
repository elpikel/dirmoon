# dirmoon

dirmoon turns a plain-language business description into a ranked list of search niches worth going after, and writes a Brief and a Page for the one the owner picks. It exists to answer "does anyone search for this?" before anything is built.

## Language

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
One pass of the pipeline for one business description, in one Mode, for one country and optionally one city. Stored in `research_runs`.
_Avoid_: Job, search, analysis, project

**Mode**:
Which kind of business a Research Run is for: **New Idea** (nothing exists yet) or **Existing Site** (a site with a domain and Search Console data).

**Step**:
One of the nine parts of a Research Run (Seeds, Expansion, Volumes, Filter and Group, Competition, Current Positions, Scoring, Brief and Content, Publish), each with its own status and stored output. Steps 1–7 follow each other on their own; Steps 8 and 9 start only when the owner asks.
_Avoid_: Stage, phase, task

**Step Group**:
One of the four groups the nine Steps are shown in: Frazy (Steps 1–2), Popyt (3–4), Konkurencja (5–7), Strona (8–9).
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
A Niche the owner picked to get a Brief and a Page. A Research Run can have several, chosen one at a time.

**Rejected Niche**:
A Niche the owner dropped from the results.

### Output

**Brief**:
The plan and content for one page for the Chosen Niche: title, H1, URL slug, sections as customer questions with their answers, the Phrases to cover, and the business details the owner fills in.

**Fact Tile**:
One of the three label–value tiles in a Page's hero (e.g. "Cena za dobę: [CENA]").

**Short Answer**:
The one-sentence direct answer to a Brief's first question, shown in the "W skrócie" box.

**Page**:
The page dirmoon writes from a Brief by filling the fixed template: one self-contained HTML document, one per Chosen Niche. New Idea and Existing Site can both publish it to Netlify (its Hosting Site) and download it as a Content File.
_Avoid_: Produced page, Landing page (for the record), article, post

**Content File**:
A Page downloaded as one `.html` file with its CSS inlined, ready to open or drop into a site.

**Hosting Site**:
The Netlify site a Page is published to; each page gets its own, and publishing again deploys to the same one.

**Demo Data**:
Obviously synthetic output from a demo adapter, used in dev while an external service has no credentials; the app shows "DANE TESTOWE" with the names of the services answered this way.

**Placeholder**:
Bracketed upper-case text (`[CENA]`, `[TELEFON]`, `[NAZWA FIRMY]`) marking a value the business owner must supply; the generator never fills it in, and a price, phone, e-mail or address the LLM writes is replaced by one.

**API Cost**:
What a Research Run has itself spent on paid API requests, in USD, shown on the run. Shared market data it reused and requests it had already paid for add nothing.
