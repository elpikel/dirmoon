# dirmoon

dirmoon turns a plain-language business description into a ranked list of search niches worth going after, and writes a brief and a landing page for the one the owner picks. It exists to answer "does anyone search for this?" before anything is built.

## Language

### Research

**Research Run**:
One pass of the pipeline for one business description, in one Mode, for one country and optionally one city. Stored in `research_runs`.
_Avoid_: Job, search, analysis, project

**Mode**:
Which kind of business a Research Run is for: **New Idea** (nothing exists yet) or **Existing Site** (a site with a domain and Search Console data).

**Step**:
One of the nine stages of a Research Run (Seeds, Expansion, Volumes, Filter and Group, Competition, Current Positions, Scoring, Brief and Content, Publish), each with its own status and stored output.
_Avoid_: Stage, phase, task

**Priority Service**:
One of the three to five things the business earns on, given as input to narrow the results.

### Phrases

**Phrase**:
A search query people really type, as returned by the keyword API. Stored in `keywords`.
_Avoid_: Keyword (outside table and API names), query, term

**Seed**:
A Phrase guessed by the LLM from the business description, used only as input to Expansion.

**Expansion**:
Turning Seeds into the few hundred Phrases people really type, through the keyword API.

**Volume**:
Monthly searches for a Phrase in a location: the country, and the city when given.

**CPC**:
What advertisers pay per click on a Phrase; the sign that the traffic is worth money.

**Trend**:
A Phrase's Volume over the last 12 months.

**Rejected Phrase**:
A Phrase the filter step dropped as outside the business.

### Competition

**SERP Snapshot**:
Google's top 10 results for a Phrase on a given date, each with its position and Page Type.

**Page Type**:
The label on a top-10 result: direct competitor, directory, forum, portal or blog. Weak types on the first page make a Niche attractive.

**Current Position**:
Where an Existing Site already ranks for a Phrase, from Search Console; positions 8–20 are the cheapest to push up.

### Niches

**Niche**:
A group of Phrases that share an intent, scored and offered to the owner as one thing to go after. Stored in `clusters`.
_Avoid_: Cluster (outside the table name), topic, group, segment

**Score**:
A Niche's 0–10 rating, built from Volume, CPC and the weakness of the competition.

### Output

**Brief**:
The plan for one page for the chosen Niche: title, H1, URL slug, sections as customer questions, and the Phrases to cover.

**Produced Page**:
The page dirmoon writes from a Brief by filling the fixed template. New Idea: static HTML deployed to Pagedock. Existing Site: a Content File.
_Avoid_: Landing page (for the record), article, post

**Content File**:
The Produced Page's content for an Existing Site, to be added to that site's own repo and layout.

**Placeholder**:
Bracketed text (`[CENA]`, `[TELEFON]`) marking a value the business owner must supply; the generator never fills it in.

**API Cost**:
What a Research Run has spent on paid API requests, shown on the run.
