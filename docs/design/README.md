# dirmoon: project and design handover

You are picking up **dirmoon**, a tool that turns a plain-language business description into (1) a ranked list of search niches worth going after and (2) a ready landing page for the chosen niche. Nothing is built yet. This folder holds the product spec, the design, and the list of things nobody has decided.

Read this file top to bottom before writing code. Section 9 lists what is not decided; do not guess those, ask the owner.

## 0. What is in this folder

| Path | What it is |
| --- | --- |
| `README.md` | This file: product, pipeline, data, design, screens, open questions |
| `tokens.css` | Colours and fonts as CSS variables |
| `reference/*.html` | The four screens as plain HTML using those variables. Reference only, do not ship |
| `reference/*-desktop.png`, `*-phone.png` | Screenshots of each screen at 1440 px and 390 px wide |

The designs also live on a canvas: https://claude.ai/artifact/StWpavPyobbhMBtMc9dQFt. The original product brief (Polish) is at https://claude.ai/artifact/5NCkKWLPwnXGLvfxi1UCwo. This README supersedes both where they differ.

## 1. Product in one paragraph

The owner tests a new business idea roughly every week and keeps building before checking demand. dirmoon answers "does anyone search for this?" before code is written. The user describes a business, picks a country and optionally a city, and the tool finds the phrases people really type, how many search for them, what a click costs, and who answers them today. It groups phrases into niches, scores them, lets the user pick one, then writes a brief and a page for it.

**Version 1 has one user: the owner.** It solves his problem first; a product for others comes only if it changes his decisions. So: no accounts, no billing, no onboarding, no multi-tenant work. A single shared password or network-level protection is enough.

**Out of scope for v1:** rank tracking over time, technical site audits, link building, any Google Ads campaign management.

## 2. Two modes, one pipeline

| | New idea | Existing site |
| --- | --- | --- |
| Input | Description, country, optional city | Same, plus the site's domain |
| Step 6 (current positions) | Skipped | Runs against Search Console |
| End product | Landing page deployed to Pagedock, with Plausible | Content file for a subpage, to be added to the site's own repo |
| Primary button on the last screen | "Opublikuj na Pagedock" | "Pobierz plik treści" |

The reference screens show the **new idea** mode (a camper rental in Trójmiasto). The first real test case, however, is an **existing site**: kkadwokat.pl, a law firm site the owner is doing SEO for. Build both modes.

## 3. Input

| Field | Example | Required |
| --- | --- | --- |
| Business description, free text | "Wynajem kamperów w Trójmieście. Trzy auta, odbiór w Gdańsku…" | Yes |
| Mode | New idea / existing site | Yes |
| Country and language | Poland, Polish | Yes |
| City or region | Trójmiasto | No |
| Domain | kkadwokat.pl | Existing site only |
| Priority services | 3–5 things the business earns on | No, but it narrows results a lot |

## 4. Pipeline

Nine steps, each its own background job, with one human decision after step 7. Persist every step's output so a run can resume and so a prompt change never re-buys API data.

1. **Seeds.** LLM turns the description into 10–20 seed phrases and a list of questions customers ask. Structured output.
2. **Expansion.** A keyword API expands the seeds into a few hundred phrases people really type. **The LLM must not invent final phrases**: it guesses wordings nobody searches.
3. **Volumes.** Per phrase: monthly searches in the country and in the city, CPC, 12-month trend.
4. **Filter and group.** LLM drops phrases outside the business and groups the rest into niches by intent.
5. **Competition.** For the best ~30 phrases, fetch Google's top 10 and label each result: direct competitor, directory, forum, portal, blog. A niche is attractive when weak page types hold the first page.
6. **Current positions.** Existing site only: phrases where the site already ranks 8–20 in Search Console. These are the cheapest to push up.
7. **Scoring.** Each niche gets a 0–10 score from volume, CPC and weakness of competition. The user picks a niche here.
8. **Brief and content.** LLM writes a brief (title, H1, URL slug, sections as questions, phrases to cover) and fills a **fixed** page template. The LLM writes content only, never layout.
9. **Publish.** New idea: deploy static HTML to Pagedock with Plausible. Existing site: produce a content file.

Why CPC matters: volume only says people search; a high CPC says someone already pays for that traffic, which is the better sign that the niche is worth money.

## 5. External systems

| System | Used for | Steps | Notes |
| --- | --- | --- | --- |
| LLM API | Seeds, filter, grouping, brief, content | 1, 4, 8 | Provider not chosen |
| DataForSEO Keywords Data API | Phrase expansion, volumes, CPC, trend by location | 2, 3 | Google Ads data without a developer token. Up to 1000 keywords per request. Pay per request |
| DataForSEO SERP API | Top 10 Google results for a phrase | 5 | Price per query not checked |
| Google Search Console API | The site's own queries and positions | 6 | Free; needs OAuth from the domain owner |
| Pagedock | Hosting the landing page | 9 | The owner's own static hosting platform. Deploy interface: ask the owner |
| Plausible | Traffic and conversions after publishing | 9 | Already used by the owner |

**Unverified, check before relying on them:**

- DataForSEO price. A third-party listing put it at about $0.09 per request of up to 1000 Google keywords. Their own pricing page was not opened. Confirm at https://dataforseo.com/pricing/keywords-data.
- City-level data. Whether DataForSEO returns useful volumes for a Polish city (rather than only the country) has not been tested. Expect niche phrases to come back as 0 or 10 at city level. Fallback already agreed in principle: use country volume plus a local variant of the phrase ("… Gdańsk"), and treat the city number as a supporting signal.
- Google Ads API was considered as a free alternative and set aside: it needs a developer token and approval, and accounts without ad spend may get ranges instead of exact numbers.

Show the API cost of each run in the UI (the designs have a `[KOSZT]` slot on screens 1 and 2).

## 6. Data model

Store everything paid for. Keep raw API responses next to the parsed rows as `jsonb`.

| Table | Holds |
| --- | --- |
| `research_runs` | Input, mode, per-step status, cost |
| `keywords` | Phrase, language, origin (seed or expansion) |
| `keyword_metrics` | Volume, CPC, trend per phrase and location, fetched-at date |
| `serp_snapshots` | Top 10 per phrase: URL, position, page type, date |
| `clusters` | Niche, its phrases, score and score components |
| `pages` | Brief, content, published URL |

`keyword_metrics` is shared across runs, so the owner's own phrase database grows over time.

## 7. Stack

The owner is an Elixir/Phoenix developer and expects:

- Phoenix with LiveView for the UI (the run screen updates live as steps finish).
- Oban for the nine jobs.
- Postgres.
- `Req` for HTTP clients.

Whether this is a standalone Phoenix app or a module inside the owner's existing idea-validation tool is **not decided** (section 9).

## 8. Design

### 8.1 Rules

- **Match the reference.** The look is deliberately the same family as the owner's other product, Ditstar: off-white dotted page, floating nav card, a large tight headline with a lime hand-drawn underline, and the tool itself inside one dark slate panel with a soft shadow.
- **Use `tokens.css`.** No new colours. The accent (`--accent`, lime) appears on one primary action per view, on "done" status, and on the headline underline. Text on the accent is always `--ink`.
- **Interface language is Polish.** Keep the copy in the reference as written, except the items listed in section 9.
- **Real elements.** Buttons are `<button>`, links are `<a href>`, inputs have a `<label>`. Buttons and links are at least 44 px tall; chips and filter pills are 36 px.
- **Every screen works at 390 px wide.** See the phone screenshots. Wide tables scroll inside their own box.
- **Fonts:** Inter (400–800) and JetBrains Mono (400, 500). The reference loads them from Google Fonts; self-host them in the app.
- **All numbers in the reference are invented.** Volumes, CPC, scores, phrase counts and niches are example data. Never copy them into seeds, fixtures presented as real, or marketing.
- **Bracketed text is a placeholder** (`[KOSZT]`, `[CENA]`, `[TELEFON]`, `[ODPOWIEDŹ]`…). It marks a value the system or the business owner supplies. The page generator must never invent prices, phone numbers, addresses or factual claims; leave a visible placeholder when a value is missing.

### 8.2 Shared pieces

| Piece | Spec |
| --- | --- |
| Page | `--page` background with a dot grid: `radial-gradient(var(--dot) 1.2px, transparent 1.2px)`, 22 px pitch. Content column max 1180 px, 32 px side padding |
| Nav card | Floating, `--page` fill, 1 px `--line` border, radius 18, shadow `0 12px 32px rgba(23,26,33,.08)`. Left: moon mark + "dirmoon" (800 weight, 21 px). Right: "Wyniki", "Strony", and a dark "Nowy research" button |
| Eyebrow tag | JetBrains Mono 12 px, uppercase, 0.1em tracking, `--chip` fill, radius 6 |
| Headline | Inter 800, tight tracking (-0.04 to -0.045em), line-height ~1. One phrase carries the underline |
| Underline | An SVG path stroked in `--accent`, 7 px, round caps, placed behind the text. Path is in the reference HTML |
| Dark panel | `--slate` fill, radius 16, shadow `0 32px 80px rgba(23,26,33,.2)`. Top bar in mono (`dirmoon / <context>` left, a note right). Under it a status row on `--slate-raised`: moon mark + one first-person sentence saying what the tool found or is doing |
| Mark | Crescent moon, single path, in the reference HTML. Placeholder quality; the owner has not approved a logo |

The status sentence is part of the product's voice: first person, one line, concrete ("Sprawdzam, kto odpowiada na najlepsze frazy. Po kroku 7 wybierasz niszę."). Generate it from run state, not from the LLM.

### 8.3 Screens

**1. New research** (`reference/new-research.html`)

- Hero: eyebrow, headline, one paragraph.
- Prompt box: white, 1.5 px `--ink` border, radius 22, a lime edge under it (`0 6px 0 var(--accent)` in the shadow). Textarea at 21 px, grows with content. Footer strip on `--page-alt` with pill chips: mode (dark, dropdown), country · language, city, then dashed "+ Domena" and "+ Usługi" for the optional fields. "Uruchom research" button on the right; it wraps below the chips on narrow screens.
- Under the box: three example prompts that fill the textarea when clicked, and the estimated API cost.
- Dark panel "jak to działa": four columns summarising the nine steps (01–02 Frazy, 03–04 Popyt, 05–07 Konkurencja, 08–09 Strona).
- Choosing "Istniejąca strona" in the mode chip makes the domain required.

**2. Research in progress** (`reference/run.html`)

- Dark panel split in two. Left: the nine steps, each with number, name, a one-line result, and a status: `Gotowe` (lime check), `W toku` (lime pill, row highlighted), `Czeka`, `Pominięty` (step 6 in new-idea mode).
- Right: detail of the running step. For step 5: progress "12 z 30", a bar, and the latest phrases checked with who ranks for them (lime = weak competition, grey = medium, `--warn` amber = strong).
- Actions: "Pokaż dotychczasowe frazy" (opens results so far), "Zatrzymaj", and the API cost so far.
- Updates live. When step 7 finishes, go to screen 3.

**3. Results** (`reference/results.html`)

- Headline states the outcome ("Dziewięć nisz. Trzy warte zajęcia."); generate it from the counts.
- Dark panel in three columns, modelled on an inbox:
  - Left: views (`Nisze`, `Wszystkie frazy`, `Odrzucone`) with counts, the run's parameters, "Eksport CSV".
  - Middle: niches sorted by score, each with score, monthly volume and a one-line competition verdict. Niches scoring under 4 are collapsed behind one row.
  - Right: the selected niche. Title, a two-sentence reading of it, three stat tiles, a table of its phrases (country volume, city volume, CPC, who holds the top 10), and actions: "Wybierz niszę i napisz stronę" (primary, starts step 8), "Wszystkie N fraz", "Odrzuć niszę".
- The third stat tile depends on mode: new idea shows direct competitors in the top 10; existing site shows the site's best current position.

**4. Brief and page** (`reference/page.html`)

- Dark panel in two columns.
- Left, the brief, all editable: page title, URL, sections as an ordered list of customer questions, phrases to cover (primary one in lime), and the two actions. The primary action follows the mode (section 2).
- Right, a live preview of the produced page inside a light browser frame. Editing the brief re-renders it.

### 8.4 The produced page template

This is the page dirmoon generates, so it is a product output, not app UI. It is a fixed template; only the content varies.

1. Site header: business name, three nav links, a dark call-to-action button.
2. Hero on `--page`: breadcrumb in mono, H1 (44 px, 800), a two-sentence intro, primary call to action plus phone, and three fact tiles.
3. "Na tej stronie" strip: pills that jump to each section.
4. One section per question from the brief: numbered badge (first one lime), the question as H2, the answer. The first section also has a "W skrócie" box with a one-sentence direct answer.
5. Closing band on `--ink`: a short prompt, contact details, a lime button.

The template is styled in dirmoon's look for now. Whether produced pages should instead take the client's own branding is open (section 9). For existing sites the output is content for the site's own layout, so only the structure above carries over.

Generated legal, medical or financial answers must be approved by the business owner before publishing; the status line on screen 4 should say so in existing-site mode.

## 9. Open questions: ask, do not guess

1. **Hero headline on screen 1.** The owner rejected two versions and has not confirmed the current one ("Zanim zbudujesz, sprawdź, czy ktoś tego szuka."). He wants it catchy and either explaining what the tool does or naming the problem. Treat it as a draft.
2. **Name.** The owner typed "dirmoon". It may be a typo for "ditmoon" (pairing with Ditstar). Confirm before buying a domain or naming a repo.
3. **Logo.** The crescent is a stand-in.
4. **Standalone app or a module** in the owner's existing idea-validation tool.
5. **Pagedock deploy interface** and how Plausible is attached to a deployed page.
6. **LLM provider and model.**
7. **Scoring formula:** the weights for volume, CPC and competition weakness.
8. **How many phrases go through the SERP check per run**, and what that costs.
9. **City-level volumes:** usable or not (see section 5).
10. **Extra brief fields.** The page template shows fact tiles, the "W skrócie" box and the jump strip. The brief as specified does not produce them. Either add three fields to the brief or drop them from the template.
11. **Existing-site output:** is a content file enough, or should the tool open a pull request in the site's repo?
12. **Produced page branding:** dirmoon's look or the client's.
13. **For kkadwokat.pl:** which 3–5 case types the firm wants to win.

## 10. Build order

Build the part with the unknown first.

1. Steps 1–3 and a plain phrase table. Run it on kkadwokat.pl and look at whether Polish and Gdańsk-level data is usable. Stop and report if it is not.
2. Steps 5 and 7: competition and scoring.
3. Step 4: filter and grouping into niches.
4. Step 6: Search Console.
5. Steps 8–9: brief, template, publish.
6. Apply the designs. Screens 2 and 3 are the ones the owner will live in; screen 1's hero is the least settled.

## 11. Done when

- A run from description to scored niches completes for both modes, and resuming a failed run does not re-buy data already stored.
- Each run shows its API cost.
- The four screens match the reference at 1440 px and 390 px, using only `tokens.css` colours.
- A produced page contains no invented price, phone, address or factual claim; missing values show as placeholders.
- A subpage for kkadwokat.pl built from a brief shows up in Search Console for its target phrase.
- The owner's own bar for "it works": after 5 runs, the tool led to at least one decision (drop an idea or pursue it) he would not have made without it. This was proposed to him, not confirmed.
