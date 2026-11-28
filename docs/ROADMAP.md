# dirmoon: where it is and where it is going

Written 27 November 2026; "Today" and stage 3 updated on 28 November 2026, when paid access was built. What dirmoon is today comes from the code and the README. The direction comes from the owner's answers on that day. The order of the stages and the items inside them are a proposal, marked as such, for the owner to change.

## The direction, as the owner set it

- **Idea validation stays the core.** dirmoon's first job is to answer "is this idea worth building?" before anything is built. Watching a live site is an add-on for people who went on to build.
- **Three audiences:** people testing ideas, small business owners with a site, and freelancers and agencies who do SEO for several client sites.
- **Paid through Stripe, and nothing is free:** every user pays before they use dirmoon, either $10 for a single research to try it, or a monthly subscription.
- **A site watch, later:** dirmoon keeps checking a site and emails its owner a list of things to improve.
- **Undecided:** whether dirmoon ever builds or publishes pages again, or stays an adviser that writes the plan and the text.

## Today

dirmoon is built and tested, and is not live yet.

What a person can do with it:

- **Test an idea.** Describe a business in a sentence and pick a country (and a city). dirmoon finds what people really type into Google, how often, what an ad click costs and who holds Google's first page, groups that into Niches and scores each from 0 to 10.
- **Check what competitors charge.** For a Niche, dirmoon opens competitors' pages and lists the prices they publish.
- **Get a Brief.** For the chosen Niche, dirmoon writes the plan and the text of one page, to hand to whoever builds the site.
- **Check an existing site.** Paste the address and dirmoon reads up to 50 pages and says in plain English what to fix: whether Google can find and read the site, whether each page says what it offers, whether it works on a phone, whether it looks like a real business, and which searched topics have no page.
- **Connect Search Console** (optional), so the site's positions are Google's own figures.
- **Pay for it.** Buy one research for $10, or start the monthly plan, $49 for 10 researches a month, on Stripe's own pages. The "Plan" screen shows the researches left and the plan's state, and opens Stripe's page to change the card or cancel. Each research includes up to 3 briefs and up to 3 competitor price checks. Paying has never been run against Stripe.

How it works today, and what that limits:

| Today | What it limits |
|---|---|
| Every research is started by hand and happens once | Nothing is checked again later; nobody is told when something changes |
| Anyone can sign up, with an emailed link; every research is paid for, except in an Account the owner marks Unpaid Access, and each has a cap on briefs and price checks | Paying has never run against Stripe; one plan only; a refund in Stripe doesn't take a research back; no VAT is charged |
| An Account can connect one Search Console account; nothing groups work by site | Awkward for someone looking after several clients' sites |
| The only emails are sign-in links | No results or reminders reach the owner outside the app |
| Only part of OpenAI (starting ideas, grouping, labelling Google's first pages) and part of DataForSEO (phrase ideas, Google's first pages) have run on real data; the rest of OpenAI (Briefs, competitor prices, "Read my site", page matching), the rest of DataForSEO, Search Console, the speed check and Stripe were built from their documentation | Those have never been run against the live services |

## The stages

### Stage 1. Go live and prove it on real data

The aim: dirmoon runs on dirmoon.com and its results are checked against reality.

- Deploy on Coolify with the production keys, mail through Brevo.
- Run the first real researches: one new idea, one existing site. Compare the cost each Run shows with what the services actually charged.
- Run dirmoon on dirmoon.com and fix what its own Site Scan reports.
- Fix what the live services expose. Their clients have only ever met test stand-ins, so expect surprises.
- Publish the Google sign-in app, so Search Console connections stop expiring after 7 days and anyone can connect.
- Say on screen when a Search Console connection has stopped working. Today the screen keeps saying "connected".

Done when: a stranger can sign up, run a research and get a result that holds up, and the owner knows what one research costs.

### Stage 2. Make the idea check something people come back to

The aim: the core product is good enough that people use it for their next idea too. Everything in this stage is a proposal.

- Compare ideas side by side: last month's idea next to this week's, by score, demand and competition.
- Check an idea again later and see what changed since the first research.
- Share a result with a partner or a client by link.
- Collect what the first users get stuck on, and fix that before adding anything else.

Done when: people who tested one idea come back to test a second.

### Stage 3. Charge for it

The aim: dirmoon pays for the data it buys. The owner chose a monthly subscription and a one-off research.

Built on 28 November 2026, not live yet (ADR-0004):

- One research for $10 paid once, which never expires, and one monthly plan, $49 for 10 researches a month that don't carry over.
- No free research: starting one spends a paid research. An Account the owner marks Unpaid Access is the only exception.
- Caps per research: up to 3 briefs and up to 3 competitor price checks.
- Stripe's own pages for paying, and Stripe's customer portal to change the card or cancel. Stripe makes an invoice for each month of the plan; a one-off payment gets a receipt.
- The "Plan" screen, and a pricing section on the landing page.

Still open:

- Run it once against Stripe's sandbox, then live (see `docs/stripe-setup.md`).
- VAT: Stripe Tax is off, so no tax is charged; turning it on needs tax registrations and a choice of whether the prices include tax.
- What happens on a refund: a refund in Stripe doesn't take a research back.
- Terms and privacy pages (the owner supplies them).
- More than one plan, and upgrading between them.

Done when: a user can subscribe, hit a limit and cancel without the owner's help, against Stripe's live service.

### Stage 4. The site watch

The aim: someone who built their site keeps getting told what to improve, without opening dirmoon. The owner asked for this; how it works is a proposal.

- The owner of a site switches the watch on for it.
- dirmoon scans the site again on a schedule and compares the result with last time.
- An email lists what to fix first, what got better and what got worse, in the same plain English as the "Your site" screen.
- With Search Console connected, the email also says which topics moved up or down in Google.

Done when: a site owner gets a useful email every period and can act on it without logging in.

To decide first: how often it runs, whether each check buys the paid keyword data again or only refreshes what is free (Search Console, the page reads, the speed test), and which plan includes it.

### Stage 5. Several sites, several people

The aim: a freelancer or an agency can run dirmoon for all their clients. Everything in this stage is a proposal.

- Several sites under one Account, each with its own researches, scans, watch and Search Console connection.
- Several people in one Account.
- A report per client that can be sent on as it is.
- Plans priced by the number of watched sites.

Done when: one person can look after ten client sites from one Account.

## Decisions still open

- **Pages:** does dirmoon ever build and publish the page, or does it stop at the Brief? The first version cut publishing.
- **Pricing:** decided (27 Nov 2026): a single research for $10 as a one-off payment, to try dirmoon, and one plan at $49 a month for 10 researches. Built with caps of 3 briefs and 3 competitor price checks per research, set in config. Still open: whether the price includes VAT, and what a refund does.
- **The watch:** how often, what it re-buys, who can switch it on.
- **Google's verification** of the sign-in app: without it people see a warning and Google caps the app at 100 users. It needs a privacy policy page and a short video.
- **Name and logo:** the handover lists both as unconfirmed; the crescent is a stand-in.
- **Language of the app:** English today; the audience is global.
- **Order of the stages:** since nothing is to be free, charging (stage 3) has to be in place before strangers can sign up, so it moves ahead of stage 2 and becomes part of going live, unless dirmoon first goes live for the owner alone.
