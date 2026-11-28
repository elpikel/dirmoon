defmodule DirmoonWeb.ResultsLiveTest do
  use DirmoonWeb.ConnCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  import Phoenix.LiveViewTest

  alias Dirmoon.Accounts.Membership
  alias Dirmoon.Billing
  alias Dirmoon.Niches.Niche
  alias Dirmoon.Pages.Page
  alias Dirmoon.PriceChecks.CompetitorOffer
  alias Dirmoon.PriceChecks.PriceCheck
  alias Dirmoon.Repo
  alias Dirmoon.Research
  alias Dirmoon.Research.RunStep
  alias Dirmoon.SiteScans
  alias Dirmoon.Workers.CheckCompetitorPrices
  alias Dirmoon.Workers.WriteBrief

  test "the heading above the Niche list counts the Niches on offer and those worth going after", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)

    for score <- ["7.3", "5.1", "4.0", "3.9", "3.2", "2.6", "2.1", "1.4", "0.8"] do
      insert(:niche, run: run, score: Decimal.new(score))
    end

    insert(:niche, run: run, score: Decimal.new("9.9"), status: :rejected)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#app-main #results h1#results-headline", "Nine topics. Three worth going after.")
    assert has_element?(view, "#app-main #results #results-views")
    assert has_element?(view, "#app-main #results #niches")
    assert has_element?(view, "#app-nav #nav-runs[aria-current=page]")
    refute has_element?(view, "#results-panel")
    refute has_element?(view, "#results-context")
  end

  test "the results show in full what the owner wrote when starting the research", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})

    description =
      "An online tool that checks whether people look for a business idea before you build it. For founders and small business owners."

    run = scored_run(scope, %{description: description, priority_services: ["idea checks", "reports"]})
    insert(:niche, run: run, score: Decimal.new("7.3"))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#run-parameters", "What you asked about")
    assert has_element?(view, "#run-parameters #run-description", description)
    assert has_element?(view, "#run-services", "Services: idea checks, reports")

    plain = scored_run(scope)
    insert(:niche, run: plain, score: Decimal.new("7.3"))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{plain}/results")

    refute has_element?(view, "#run-services")
  end

  test "each view says what it holds, in the list of views and above its own list", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    insert(:niche, run: run, score: Decimal.new("7.3"))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#results-views", "What I found")
    assert has_element?(view, "#view-niches", "Topics")

    assert has_element?(
             view,
             "#view-niches [data-part=hint]",
             "Searches about the same thing, put together. Start here."
           )

    assert has_element?(view, "#view-phrases", "All searches")

    assert has_element?(
             view,
             "#view-phrases [data-part=hint]",
             "Each exact thing people type into Google, and how often."
           )

    assert has_element?(view, "#view-rejected", "Searches I left out")
    assert has_element?(view, "#view-rejected [data-part=hint]", "Searches I didn't use, and why.")

    assert has_element?(
             view,
             "#results-explainer",
             "People ask Google for the same thing in many different words. A topic is those searches put together."
           )

    assert has_element?(view, "#results-explainer", "Each row is one topic, the best first.")

    assert has_element?(
             view,
             "#results-explainer",
             "then choose it and I'll write the plan and the text for one page about it."
           )

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?view=phrases")
    assert has_element?(view, "#results-explainer", "Every search I kept: what people type into Google")

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?view=rejected")
    assert has_element?(view, "#results-explainer", "Searches I left out of the topics, each with the reason.")
  end

  test "the Niches are listed by Score with a plain verdict, monthly searches and the competition", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    second = insert(:niche, run: run, score: Decimal.new("5.2"), name: "Nisza druga testowa")
    first = insert(:niche, run: run, score: Decimal.new("6.7"), name: "Nisza pierwsza testowa")
    checked = phrase_in_niche(run, first, %{volume: 1_234, cpc: "0.31"})
    phrase_in_niche(run, second, %{volume: 57, cpc: nil})
    insert(:serp_assessment, run: run, phrase: checked.phrase, labels: labels(%{"forum" => 6, "blog" => 4}))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#niches li:nth-child(2)#niche-row-#{first.id}")
    assert has_element?(view, "#niche-row-#{first.id} [data-part=advice].text-accent", "Worth a try")

    assert has_element?(
             view,
             "#niche-row-#{first.id} [data-part=figures]",
             "Typed 1,234 times a month · weak competition, easy to get onto Google's first page"
           )

    assert has_element?(
             view,
             "#niche-row-#{second.id} [data-part=figures]",
             "Typed 57 times a month · competition not checked yet"
           )
  end

  test "a Niche worth going after against strong competition is marked as hard, in the warning colour", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("4.4"))
    checked = phrase_in_niche(run, niche, %{volume: 20, cpc: nil})
    insert(:serp_assessment, run: run, phrase: checked.phrase, labels: labels(%{"direct_competitor" => 7, "portal" => 3}))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#niche-row-#{niche.id} [data-part=advice].text-warn", "Worth it, but hard")

    assert has_element?(
             view,
             "#niche-row-#{niche.id} [data-part=figures]",
             "Typed 20 times a month · strong competition, hard to get onto Google's first page"
           )

    assert has_element?(view, "#niche-advice[data-kind=hard] #niche-advice-label.text-warn", "Worth it, but hard")

    assert has_element?(
             view,
             "#niche-advice-competition",
             "Strong competition: Google's first page today holds mostly businesses like yours, big portals. Getting onto it will be hard and slow."
           )
  end

  test "Niches scoring under 4 are collapsed behind one row that expands on click", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    worth = insert(:niche, run: run, score: Decimal.new("4.6"))
    low = Enum.map(["3.1", "1.7"], &insert(:niche, run: run, score: Decimal.new(&1)))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#niche-row-#{worth.id}")
    assert has_element?(view, "#collapsed-niches", "+ 2 topics rated below 4 out of 10")

    for niche <- low do
      refute has_element?(view, "#niche-row-#{niche.id}")
    end

    view |> element("#collapsed-niches") |> render_click()

    for niche <- low do
      assert has_element?(view, "#niche-row-#{niche.id}")
    end

    refute has_element?(view, "#collapsed-niches")
  end

  test "the selected Niche shows its title, reading, the verdict with its reasons, three stat tiles and its Phrases", %{
    conn: conn
  } do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope, %{city: "Płock", city_location_code: 9_990_777})

    niche =
      insert(:niche,
        run: run,
        score: Decimal.new("6.4"),
        name: "Czartery testowe",
        reading: "Pierwsze zdanie testowe. Drugie zdanie testowe."
      )

    checked = phrase_in_niche(run, niche, %{volume: 2_345, cpc: "0.40"})
    insert(:metrics, phrase: checked.phrase, location_code: 9_990_777, search_volume: 13)
    unchecked = phrase_in_niche(run, niche, %{volume: 655, cpc: "1.20"})
    insert(:serp_assessment, run: run, phrase: checked.phrase, labels: labels(%{"blog" => 5, "directory" => 5}))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#niche-detail", "topic · 2 searches · rating 6 out of 10")
    assert has_element?(view, "#niche-advice[data-kind=worth] #niche-advice-label.text-accent", "Worth a try")

    assert has_element?(
             view,
             "#niche-advice-demand",
             "People type these searches into Google about 3,000 times a month."
           )

    assert has_element?(view, "#niche-advice-value", "Businesses pay Google $0.57 on average for one ad click")

    assert has_element?(
             view,
             "#niche-advice-competition",
             "Weak competition: Google's first page today holds mostly guides and blogs, business directories, not offers from businesses like yours."
           )

    assert has_element?(
             view,
             "#niche-next-step",
             "Once you choose, I'll write a brief: the plan and the text for one page about this topic"
           )

    assert has_element?(view, "#niche-detail h2", "Czartery testowe")
    assert has_element?(view, "#niche-detail", "Pierwsze zdanie testowe. Drugie zdanie testowe.")
    assert has_element?(view, "#niche-stats #niche-stat-volume", "3,000")
    assert has_element?(view, "#niche-stats #niche-stat-cpc", "$0.57")
    assert has_element?(view, "#niche-stats #niche-stat-volume", "Times a month people type these")
    assert has_element?(view, "#niche-stats #niche-stat-cpc", "What businesses pay Google for one ad click")
    assert has_element?(view, "#niche-stats #niche-stat-competitors [data-part=value]", "0 of 10")
    assert has_element?(view, "#niche-phrases-volumes[colspan='2']", "How many times a month people type it")
    assert has_element?(view, "#niche-phrases-country", "Poland")
    assert has_element?(view, "#niche-detail th", "Search")
    assert has_element?(view, "#niche-detail th", "Ad click price")
    assert has_element?(view, "#niche-detail th", "Who is on Google's first page")
    assert has_element?(view, "#niche-phrases-city", "Płock")
    assert has_element?(view, "#page-type-direct_competitor dt", "businesses like yours")
    assert has_element?(view, "#page-type-directory dd", "Business listings and comparison sites.")
    assert has_element?(view, "#page-type-blog [data-part=site] a", "wynik-1.example")
    assert has_element?(view, "#page-type-directory [data-part=site]", "wynik-6.example")
    refute has_element?(view, "#page-type-forum [data-part=sites]")
    assert has_element?(view, "#niche-phrases-#{checked.id}", checked.phrase.phrase)
    assert has_element?(view, "#niche-phrases-#{checked.id}", "2,345")
    assert has_element?(view, "#niche-phrases-#{checked.id}", "13")
    assert has_element?(view, "#niche-phrases-#{checked.id}", "$0.40")
    assert has_element?(view, "#niche-phrases-#{checked.id}", "guides and blogs, business directories")

    assert has_element?(
             view,
             "#niche-phrases-#{checked.id} [data-part=sites]",
             "wynik-1.example, wynik-2.example, wynik-3.example"
           )

    assert has_element?(
             view,
             "#niche-phrases-#{checked.id} a[data-part=more-sites][href='#first-page-#{checked.id}']",
             "and 7 more"
           )

    refute has_element?(view, "#niche-phrases-#{unchecked.id} [data-part=sites]")
    assert has_element?(view, "#niche-phrases-#{unchecked.id}", "—")
  end

  test "each checked Phrase lists the sites on Google's first page with their type, the first one open", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("6.4"))
    first = phrase_in_niche(run, niche, %{volume: 900, cpc: nil})
    second = phrase_in_niche(run, niche, %{volume: 500, cpc: nil})
    empty = phrase_in_niche(run, niche, %{volume: 300, cpc: nil})
    unchecked = phrase_in_niche(run, niche, %{volume: 100, cpc: nil})

    results = [
      %{
        "position" => 1,
        "url" => "https://lodowisko-testowe.example/wypozyczalnia",
        "domain" => "lodowisko-testowe.example",
        "title" => "Wypożyczalnia testowa"
      },
      %{"position" => 2, "url" => "javascript:alert(1)", "domain" => "dziwny-adres.example", "title" => nil},
      %{"position" => 3, "url" => "http://bez-typu.example/", "domain" => "bez-typu.example", "title" => "Bez typu"}
    ]

    insert(:serp_assessment,
      run: run,
      phrase: first.phrase,
      serp_snapshot: build(:serp_snapshot, phrase: first.phrase, results: results),
      labels: [%{"position" => 1, "page_type" => "direct_competitor"}, %{"position" => 2, "page_type" => "portal"}]
    )

    insert(:serp_assessment, run: run, phrase: second.phrase, labels: labels(%{"blog" => 10}))

    insert(:serp_assessment,
      run: run,
      phrase: empty.phrase,
      serp_snapshot: build(:serp_snapshot, phrase: empty.phrase, results: []),
      labels: []
    )

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#first-page-#{first.id}[open] summary [data-part=first-page-phrase]", first.phrase.phrase)

    assert has_element?(
             view,
             "#first-page-#{first.id} summary [data-part=first-page-label]",
             "When someone types into Google:"
           )

    assert has_element?(
             view,
             "#niche-phrases-#{first.id} [data-part=sites]",
             "lodowisko-testowe.example, dziwny-adres.example, bez-typu.example"
           )

    refute has_element?(view, "#niche-phrases-#{first.id} [data-part=more-sites]")
    assert has_element?(view, "#niche-phrases-#{empty.id}", "no results")
    refute has_element?(view, "#niche-phrases-#{empty.id} [data-part=sites]")
    assert has_element?(view, "#first-page-#{first.id} summary", "3 results")

    assert has_element?(
             view,
             "#first-page-#{first.id} a[href='https://lodowisko-testowe.example/wypozyczalnia'][rel~=noopener]",
             "lodowisko-testowe.example"
           )

    assert has_element?(view, "#first-page-#{first.id} li:nth-child(1)", "Wypożyczalnia testowa")
    assert has_element?(view, "#first-page-#{first.id} li:nth-child(1) [data-part=page-type]", "business like yours")
    assert has_element?(view, "#first-page-#{first.id} li:nth-child(2)", "dziwny-adres.example")
    refute has_element?(view, "#first-page-#{first.id} li:nth-child(2) a")
    assert has_element?(view, "#first-page-#{first.id} li:nth-child(2) [data-part=page-type]", "big portal")
    assert has_element?(view, "#first-page-#{first.id} li:nth-child(3) a[href='http://bez-typu.example/']")
    refute has_element?(view, "#first-page-#{first.id} li:nth-child(3) [data-part=page-type]")

    assert has_element?(view, "#first-page-#{second.id}:not([open]) summary", "10 results")
    assert has_element?(view, "#first-page-#{second.id} [data-part=page-type]", "guide or blog")
    assert has_element?(view, "#first-page-#{empty.id}", "Google showed no results for this search.")
    refute has_element?(view, "#first-page-#{unchecked.id}")

    assert has_element?(
             view,
             "#page-type-direct_competitor [data-part=site] a[href='https://lodowisko-testowe.example/wypozyczalnia']",
             "lodowisko-testowe.example"
           )

    assert has_element?(view, "#page-type-portal [data-part=site]", "dziwny-adres.example")
    refute has_element?(view, "#page-type-portal [data-part=site] a")
    refute has_element?(view, "#page-type-legend", "bez-typu.example")
  end

  test "a site found on several first pages is listed once under its type, with how many times", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("6.4"))

    for volume <- [900, 500] do
      checked = phrase_in_niche(run, niche, %{volume: volume, cpc: nil})
      insert(:serp_assessment, run: run, phrase: checked.phrase, labels: labels(%{"forum" => 10}))
    end

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert view
           |> element("#page-type-forum [data-part=sites]")
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("[data-part=site]")
           |> Enum.count() == 10

    assert has_element?(view, "#page-type-forum [data-part=site]:first-child", "×2")
  end

  test "a Niche with no checked Phrase has no first-page lists", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("6.4"))
    phrase_in_niche(run, niche, %{volume: 900, cpc: nil})

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    refute has_element?(view, "#first-pages")
  end

  test "a run without a city has no city column", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("5.0"))
    phrase_in_niche(run, niche, %{volume: 30, cpc: nil})

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#niche-detail")
    assert has_element?(view, "#niche-phrases-volumes[colspan='1']")
    refute has_element?(view, "#niche-phrases-city")
  end

  test "a New Idea run's third tile counts direct competitors on Google's first page", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("5.5"))
    checked = phrase_in_niche(run, niche, %{volume: 30, cpc: nil})
    insert(:serp_assessment, run: run, phrase: checked.phrase, labels: labels(%{"direct_competitor" => 3, "blog" => 7}))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#niche-stat-competitors", "Competitors on Google's first page")
    assert has_element?(view, "#niche-stat-competitors [data-part=value]", "3 of 10")
    refute has_element?(view, "#niche-stat-position")
    refute has_element?(view, "#niche-phrases-position")
  end

  test "an Existing Site run's third tile and last column show the site's Current Positions", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope, %{mode: :existing_site, domain: "strona-testowa.pl"})
    niche = insert(:niche, run: run, score: Decimal.new("5.5"))
    ranked = phrase_in_niche(run, niche, %{volume: 30, cpc: nil})
    ranked |> Ecto.Changeset.change(current_position: Decimal.new("13.7")) |> Repo.update!()
    phrase_in_niche(run, niche, %{volume: 10, cpc: nil})

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#niche-stat-position", "Your best position on Google")
    assert has_element?(view, "#niche-stat-position [data-part=value]", "13.7")
    assert has_element?(view, "#niche-phrases-position", "Your position")
    assert has_element?(view, "#niche-phrases-#{ranked.id}", "13.7")
    refute has_element?(view, "#niche-stat-competitors")
    assert has_element?(view, "#run-parameters", "strona-testowa.pl")
  end

  test "international domains are shown in their Unicode form: the site's, Google's results' and competitors'", %{
    conn: conn
  } do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope, %{mode: :existing_site, domain: "xn--w-uga1v8h.pl"})
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))
    checked = phrase_in_niche(run, niche, %{volume: 900, cpc: nil})

    results = [
      %{
        "position" => 1,
        "url" => "https://xn--mnchen-3ya.de/hotel",
        "domain" => "xn--mnchen-3ya.de",
        "title" => "Hotel"
      }
    ]

    insert(:serp_assessment,
      run: run,
      phrase: checked.phrase,
      serp_snapshot: build(:serp_snapshot, phrase: checked.phrase, results: results),
      labels: [%{"position" => 1, "page_type" => "direct_competitor"}]
    )

    price_check = insert(:price_check, run: run, niche: niche, status: :done)

    competitor =
      insert(:competitor_page,
        price_check: price_check,
        domain: "xn--r8jz45g.jp",
        url: "https://xn--r8jz45g.jp/",
        outcome: :no_prices,
        facts: comparison_facts(%{})
      )

    site_scan = insert(:site_scan, run: run, status: :done, facts: %{"matching" => %{"done" => true}})
    insert(:scanned_page, site_scan: site_scan, url: "https://xn--w-uga1v8h.pl/", cluster_id: niche.id)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#run-parameters", "żółw.pl")
    assert has_element?(view, "#first-page-#{checked.id} li:nth-child(1) a", "münchen.de")
    assert has_element?(view, "#page-type-direct_competitor [data-part=site] a", "münchen.de")
    assert has_element?(view, "#competitor-page-#{competitor.id} [data-part=domain]", "例え.jp")
    assert has_element?(view, "#page-comparison-competitor-#{competitor.id} [data-part=domain]", "例え.jp")
  end

  test "an Existing Site run's views lead to \"Your site\" with a one-line hint", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope, %{mode: :existing_site, domain: "strona-testowa.pl"})
    insert(:niche, run: run, score: Decimal.new("5.5"))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, ~s(#results-views #view-site[href="/app/runs/#{run.id}/site"]), "Your site")
    assert has_element?(view, "#view-site [data-part=hint]", "What I found on your own site, and what to fix.")
  end

  test "a New Idea run's views have no \"Your site\"", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    insert(:niche, run: run, score: Decimal.new("5.5"))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    refute has_element?(view, "#view-site")
    refute has_element?(view, "[data-part=site-page]")
    refute has_element?(view, "#niche-site-page")
  end

  test "once the site's pages are matched each topic says whether the site has a page for it", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope, %{mode: :existing_site, domain: "strona-testowa.pl"})
    with_page = insert(:niche, run: run, score: Decimal.new("6.5"))
    without_page = insert(:niche, run: run, score: Decimal.new("5.5"))
    site_scan = insert(:site_scan, run: run, status: :done, facts: %{"matching" => %{"done" => true}})
    page = insert(:scanned_page, site_scan: site_scan, cluster_id: with_page.id, facts: %{"word_count" => 300})

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?#{[view: "niches", niche: with_page.id]}")

    assert has_element?(view, "#niche-row-#{with_page.id}-site-page", "You have a page: #{page.url}")
    assert has_element?(view, "#niche-row-#{without_page.id}-site-page", "No page yet")

    assert has_element?(
             view,
             ~s(#niche-site-page a[href="#{page.url}"][target=_blank][rel="noopener noreferrer nofollow"]),
             page.url
           )

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?#{[view: "niches", niche: without_page.id]}")

    assert has_element?(view, "#niche-site-page", "No page yet: your site has no page about this topic.")
  end

  test "a matched page whose address is not a web address is shown as text, never as a link", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope, %{mode: :existing_site, domain: "strona-testowa.pl"})
    niche = insert(:niche, run: run, score: Decimal.new("6.5"))
    site_scan = insert(:site_scan, run: run, status: :done, facts: %{"matching" => %{"done" => true}})

    insert(:scanned_page,
      site_scan: site_scan,
      url: "javascript:alert(1)",
      cluster_id: niche.id,
      facts: %{"word_count" => 300}
    )

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#niche-site-page", "You have a page: javascript:alert(1)")
    refute has_element?(view, "#niche-site-page a")
  end

  test "topics say nothing about the site's pages until they are matched", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope, %{mode: :existing_site, domain: "strona-testowa.pl"})
    niche = insert(:niche, run: run, score: Decimal.new("6.5"))
    site_scan = insert(:site_scan, run: run, status: :done, facts: %{})
    insert(:scanned_page, site_scan: site_scan, cluster_id: niche.id, facts: %{"word_count" => 300})

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    refute has_element?(view, "[data-part=site-page]")
    refute has_element?(view, "#niche-site-page")
  end

  test "an Existing Site run marks the Niche's Quick Wins next to their position and counts them in the summary line",
       %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope, %{mode: :existing_site, domain: "strona-testowa.pl"})
    niche = insert(:niche, run: run, score: Decimal.new("5.5"))
    quick_win = phrase_in_niche(run, niche, %{volume: 30, cpc: nil})
    quick_win |> Ecto.Changeset.change(current_position: Decimal.new("13.7")) |> Repo.update!()
    top = phrase_in_niche(run, niche, %{volume: 20, cpc: nil})
    top |> Ecto.Changeset.change(current_position: Decimal.new("2.0")) |> Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#niche-phrases-#{quick_win.id}-quick-win", "quick win")
    refute has_element?(view, "#niche-phrases-#{top.id}-quick-win")
    assert has_element?(view, "#niche-quick-win-count", "1 quick win")
  end

  test "a Niche without Quick Wins names none in its summary line", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope, %{mode: :existing_site, domain: "strona-testowa.pl"})
    niche = insert(:niche, run: run, score: Decimal.new("5.5"))
    top = phrase_in_niche(run, niche, %{volume: 20, cpc: nil})
    top |> Ecto.Changeset.change(current_position: Decimal.new("2.0")) |> Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    refute has_element?(view, "#niche-quick-win-count")
    refute has_element?(view, "[data-part=quick-win]")
  end

  test "\"All phrases\" of an Existing Site run shows each Phrase's position and marks the Quick Wins",
       %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope, %{mode: :existing_site, domain: "strona-testowa.pl"})
    niche = insert(:niche, run: run, score: Decimal.new("5.0"))
    quick_win = phrase_in_niche(run, niche, %{volume: 30, cpc: nil})
    quick_win |> Ecto.Changeset.change(current_position: Decimal.new("9.0")) |> Repo.update!()
    unranked = phrase_in_niche(run, niche, %{volume: 20, cpc: nil})

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?view=phrases")

    assert has_element?(view, "#phrases-#{quick_win.id}", "your site's position 9.0")
    assert has_element?(view, "#phrases-#{quick_win.id}-quick-win", "quick win")
    assert has_element?(view, "#phrases-#{unranked.id}", "your site's position —")
    refute has_element?(view, "#phrases-#{unranked.id}-quick-win")
  end

  test "all the Niche's Phrases show after clicking the button that names their count", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("5.5"))
    phrases = Enum.map(1..12, &phrase_in_niche(run, niche, %{volume: 100 - &1, cpc: nil}))
    last = List.last(phrases)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    refute has_element?(view, "#niche-phrases-#{last.id}")

    view |> element("#all-phrases", "All 12 searches") |> render_click()

    assert has_element?(view, "#niche-phrases-#{last.id}")
    refute has_element?(view, "#all-phrases")
  end

  test "clicking a Niche's row selects it", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    insert(:niche, run: run, score: Decimal.new("7.0"))
    other = insert(:niche, run: run, score: Decimal.new("5.0"), name: "Nisza do kliknięcia")

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")
    view |> element("#niche-row-#{other.id} a") |> render_click()

    assert_patch(view, "/app/runs/#{run.id}/results?niche=#{other.id}&view=niches")
    assert has_element?(view, "#niche-detail h2", "Nisza do kliknięcia")
    assert has_element?(view, "#niche-row-#{other.id} a[data-selected]")
  end

  test "\"All phrases\" lists the kept Phrases with their Niche, Volume and CPC", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("5.0"), name: "Nisza widoku fraz")
    kept = phrase_in_niche(run, niche, %{volume: 4_321, cpc: "0.65"})
    rejected = insert(:run_phrase, run: run, status: :rejected, rejection_reason: "poza ofertą testową")

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")
    view |> element("#view-phrases") |> render_click()

    assert_patch(view, "/app/runs/#{run.id}/results?niche=#{niche.id}&view=phrases")
    assert has_element?(view, "#view-phrases[aria-current=page] [data-part=count]", "1")
    assert has_element?(view, "#view-rejected [data-part=count]", "1")
    assert has_element?(view, "#view-niches [data-part=count]", "1")
    assert has_element?(view, "#phrases-#{kept.id}", kept.phrase.phrase)
    assert has_element?(view, "#phrases-#{kept.id}", "Topic: Nisza widoku fraz")
    assert has_element?(view, "#phrases-#{kept.id}", "typed 4,321 times a month · ad click price $0.65")
    refute has_element?(view, "#phrases-#{rejected.id}")
    refute has_element?(view, "#niches")
  end

  test "\"Rejected\" lists the Rejected Phrases with their reasons", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    insert(:niche, run: run, score: Decimal.new("5.0"))
    rejected = insert(:run_phrase, run: run, status: :rejected, rejection_reason: "poza ofertą testową")

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?view=rejected")

    assert has_element?(view, "#view-rejected[aria-current=page]", "Searches I left out")
    assert has_element?(view, "#rejected-phrases-#{rejected.id}", rejected.phrase.phrase)
    assert has_element?(view, "#rejected-phrases-#{rejected.id}", "poza ofertą testową")
  end

  test "an unknown view falls back to the Niches", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("5.0"))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?view=cokolwiek")

    assert has_element?(view, "#niche-row-#{niche.id}")
    assert has_element?(view, "#view-niches[aria-current=page]")
  end

  test "another run's Niche in the URL is ignored and the top Niche is selected", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    top = insert(:niche, run: run, score: Decimal.new("6.0"), name: "Nisza najlepsza testowa")
    foreign = insert(:niche, run: scored_run(scope), score: Decimal.new("9.0"), name: "Nisza z innego researchu")

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?niche=#{foreign.id}")

    assert has_element?(view, "#niche-detail[data-niche-id='#{top.id}']", "Nisza najlepsza testowa")
    refute has_element?(view, "#results", "Nisza z innego researchu")
  end

  test "a malformed Niche id in the URL selects the top Niche", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    top = insert(:niche, run: run, score: Decimal.new("6.0"))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?niche=nie-liczba")

    assert has_element?(view, "#niche-detail[data-niche-id='#{top.id}']")
  end

  test "choosing the Niche starts Step 8 and opens the page screen", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")
    view |> element("#choose-niche", "Choose this topic and write its brief") |> render_click()

    page = Repo.get_by!(Page, cluster_id: niche.id)
    assert_redirect(view, "/app/pages/#{page.id}")
    assert page.status == :writing
    assert_enqueued(worker: WriteBrief, args: %{run_id: run.id})
  end

  test "a choice that can't start says why", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))
    writing = insert(:niche, run: run, score: Decimal.new("5.0"), status: :chosen)
    insert(:page, run: run, niche: writing, status: :writing, brief: nil)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?niche=#{niche.id}")
    view |> element("#choose-niche") |> render_click()

    assert has_element?(view, "#flash-error", "I'm still writing the brief for another topic")
    assert Repo.get_by(Page, cluster_id: niche.id) == nil
    refute_enqueued(worker: WriteBrief)
  end

  test "a stopped run hides the choice and points to the run screen to resume it", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope, %{status: :stopped})
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#niche-detail[data-niche-id='#{niche.id}']")
    assert has_element?(view, "#results-run-stopped", "The research is stopped. Resume it to choose a topic.")
    assert has_element?(view, "#results-resume-link[href='/app/runs/#{run.id}']")
    refute has_element?(view, "#choose-niche")
    refute has_element?(view, "#reject-niche")
    refute has_element?(view, "#niche-next-step")
  end

  test "a choice on a stopped run sent anyway changes nothing", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope, %{status: :stopped})
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")
    render_hook(view, "choose", %{})
    render_hook(view, "reject", %{})

    assert Repo.get!(Niche, niche.id).status == :proposed
    assert Repo.get_by(Page, cluster_id: niche.id) == nil
    refute_enqueued(worker: WriteBrief)
  end

  test "a choice the run is too busy for says the research is still working", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    steps = 1..7 |> Map.new(&{&1, :done}) |> Map.put(8, :running) |> build_run_steps()
    run = insert(:run, account: scope.account, status: :running, steps: steps)
    written = insert(:niche, run: run, score: Decimal.new("5.0"), status: :chosen)
    insert(:page, run: run, niche: written, status: :ready)
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?niche=#{niche.id}")
    view |> element("#choose-niche") |> render_click()

    assert has_element?(view, "#flash-error", "The research is still working")
    assert Repo.get_by(Page, cluster_id: niche.id) == nil
    refute_enqueued(worker: WriteBrief)
  end

  test "crafted choose and reject events before Step 7 change nothing", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    statuses = 1..4 |> Map.new(&{&1, :done}) |> Map.put(5, :running)
    run = insert(:run, account: scope.account, status: :running, steps: build_run_steps(statuses))
    niche = insert(:niche, run: run)
    other_run_niche = insert(:niche, run: scored_run(scope))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")
    render_hook(view, "choose", %{"niche_id" => other_run_niche.id})
    render_hook(view, "reject", %{"niche_id" => other_run_niche.id})

    for untouched <- [niche, other_run_niche] do
      assert Repo.get!(Niche, untouched.id).status == :proposed
    end

    assert Repo.all(Page) == []
    refute_enqueued(worker: WriteBrief)
  end

  test "a crafted Niche id is ignored and the selected Niche is the one chosen", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    selected = insert(:niche, run: run, score: Decimal.new("6.0"))
    foreign = insert(:niche, run: scored_run(%{account: insert(:account)}), score: Decimal.new("7.0"))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?niche=#{selected.id}")
    render_hook(view, "choose", %{"niche_id" => foreign.id})

    page = Repo.get_by!(Page, cluster_id: selected.id)
    assert_redirect(view, "/app/pages/#{page.id}")
    assert Repo.get!(Niche, foreign.id).status == :proposed
    assert Repo.get_by(Page, cluster_id: foreign.id) == nil
  end

  test "a crafted Niche id on reject is ignored and the selected Niche is the one rejected", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    selected = insert(:niche, run: run, score: Decimal.new("6.0"))
    foreign = insert(:niche, run: scored_run(%{account: insert(:account)}), score: Decimal.new("7.0"))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?niche=#{selected.id}")
    render_hook(view, "reject", %{"niche_id" => foreign.id})

    assert Repo.get!(Niche, selected.id).status == :rejected
    assert Repo.get!(Niche, foreign.id).status == :proposed
  end

  test "a Niche that already has a page links to it instead of offering a choice", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("6.0"), status: :chosen)
    page = insert(:page, run: run, niche: niche)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#open-page[href='/app/pages/#{page.id}']", "Open brief")
    refute has_element?(view, "#choose-niche")
    refute has_element?(view, "#reject-niche")
    refute has_element?(view, "#niche-next-step")
  end

  test "rejecting the Niche takes it off the list, updates the counts and selects the next one", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    rejected = insert(:niche, run: run, score: Decimal.new("6.0"))
    next = insert(:niche, run: run, score: Decimal.new("5.0"), name: "Nisza następna testowa")

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")
    view |> element("#reject-niche", "Reject this topic") |> render_click()

    assert_patch(view, "/app/runs/#{run.id}/results?niche=#{next.id}&view=niches")
    assert Repo.get!(Niche, rejected.id).status == :rejected
    refute has_element?(view, "#niche-row-#{rejected.id}")
    assert has_element?(view, "#view-niches [data-part=count]", "1")
    assert has_element?(view, "#results-headline", "One topic.")
    assert has_element?(view, "#niche-detail h2", "Nisza następna testowa")
    assert has_element?(view, "#flash-info", "I rejected the topic.")
  end

  test "rejecting the last Niche leaves an empty list", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    insert(:niche, run: run, score: Decimal.new("6.0"))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")
    view |> element("#reject-niche") |> render_click()

    assert has_element?(view, "#results-headline", "Zero topics.")
    assert has_element?(view, "#niche-detail-empty")
    refute has_element?(view, "#choose-niche")
  end

  test "before Step 7 has finished the Phrases so far show without a Niche choice", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    statuses = 1..4 |> Map.new(&{&1, :done}) |> Map.put(5, :running)
    run = insert(:run, account: scope.account, status: :running, steps: build_run_steps(statuses))
    niche = insert(:niche, run: run)
    kept = phrase_in_niche(run, niche, %{volume: 80, cpc: nil})

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?view=niches")

    assert has_element?(view, "#results-headline", "What people type into Google, so far.")
    assert has_element?(view, "#phrases-#{kept.id}", kept.phrase.phrase)
    assert has_element?(view, "#view-niches[aria-disabled] [data-part=count]", "1")
    assert has_element?(view, "#back-to-run[href='/app/runs/#{run.id}']")
    refute has_element?(view, "#choose-niche")
    refute has_element?(view, "#reject-niche")
    refute has_element?(view, "#niche-detail")
  end

  test "the results fill in when Step 7 finishes while the screen is open", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    statuses = 1..6 |> Map.new(&{&1, :done}) |> Map.put(7, :running)
    run = insert(:run, account: scope.account, status: :running, steps: build_run_steps(statuses))
    niche = insert(:niche, run: run, score: Decimal.new("5.0"))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")
    refute has_element?(view, "#choose-niche")

    RunStep
    |> Repo.get_by!(run_id: run.id, number: 7)
    |> Ecto.Changeset.change(status: :done)
    |> Repo.update!()

    Research.broadcast_run_updated(run)

    assert has_element?(view, "#niche-row-#{niche.id}")
    assert has_element?(view, "#choose-niche")
    assert has_element?(view, "#results-headline", "One topic.")
  end

  test "another Account's run sends the User back to the runs list", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(%{account: insert(:account)})

    assert {:error, {:live_redirect, %{to: "/app/runs", flash: flash}}} = live(conn, ~p"/app/runs/#{run}/results")
    assert flash["error"] == "Research not found"
  end

  test "a malformed run id sends the User back to the runs list", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})

    assert {:error, {:live_redirect, %{to: "/app/runs"}}} = live(conn, "/app/runs/nie-liczba/results")
  end

  test "a signed-out visitor is sent to sign in", %{conn: conn} do
    run = scored_run(%{account: insert(:account)})

    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/app/runs/#{run}/results")
  end

  test "choosing a Niche deleted meanwhile says it was not found", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")
    Repo.delete!(niche)

    view |> element("#choose-niche") |> render_click()

    assert has_element?(view, "#flash-error", "Topic not found")
    refute_enqueued(worker: WriteBrief)
  end

  test "choosing a Niche of a run stopped meanwhile says the research is not ready", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")
    run |> Ecto.Changeset.change(status: :stopped) |> Repo.update!()

    view |> element("#choose-niche") |> render_click()

    assert has_element?(
             view,
             "#flash-error",
             "You can't choose a topic now: the research hasn't finished rating them or is stopped"
           )

    assert Repo.get_by(Page, cluster_id: niche.id) == nil
    refute_enqueued(worker: WriteBrief)
  end

  test "choosing a Niche rejected meanwhile says it can no longer be chosen", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")
    niche |> Ecto.Changeset.change(status: :rejected) |> Repo.update!()

    view |> element("#choose-niche") |> render_click()

    assert has_element?(view, "#flash-error", "This topic can no longer be chosen")
    assert Repo.get_by(Page, cluster_id: niche.id) == nil
  end

  test "rejecting a Niche deleted meanwhile says it was not found", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")
    Repo.delete!(niche)

    view |> element("#reject-niche") |> render_click()

    assert has_element?(view, "#flash-error", "Topic not found")
  end

  test "rejecting a Niche chosen meanwhile says it can no longer be rejected", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")
    niche |> Ecto.Changeset.change(status: :chosen) |> Repo.update!()

    view |> element("#reject-niche") |> render_click()

    assert has_element?(view, "#flash-error", "This topic can no longer be rejected")
    assert Repo.get!(Niche, niche.id).status == :chosen
  end

  test "a run deleted while the results are open sends the User back to the runs list", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")
    Repo.delete!(run)

    Research.broadcast_run_updated(run)

    assert {"/app/runs", %{"error" => "Research not found"}} = assert_redirect(view)
  end

  test "progress of a running Step leaves the results as they are", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    Research.broadcast_progress(run, %{step: 5, checked: 1, total: 2})

    assert has_element?(view, "#niche-row-#{niche.id}")
    assert has_element?(view, "#choose-niche")
  end

  test "more kept Phrases than the list shows say how many are shown and point to the CSV", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    insert_list(501, :run_phrase, run: run)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?view=phrases")

    assert has_element?(view, "#results", "Showing the first 500 of 501.")
  end

  test "a kept Phrase without a Volume shows dashes for its Volume and CPC", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    kept = insert(:run_phrase, run: run)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?view=phrases")

    assert has_element?(view, "#phrases-#{kept.id}", "typed — times a month · ad click price —")
  end

  test "a Niche without a Score reads as unscored", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: nil)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?niche=#{niche.id}")

    assert has_element?(view, "#niche-row-#{niche.id} [data-part=advice].text-on-app-muted", "Not rated yet")
    assert has_element?(view, "#niche-detail", "topic · 0 searches · not rated")
    assert has_element?(view, "#niche-advice[data-kind=unscored] #niche-advice-label", "Not rated yet")
    assert has_element?(view, "#niche-advice-demand", "Almost nobody types these into Google")
    assert has_element?(view, "#niche-advice-value", "Nobody pays Google for ads on these searches")
    assert has_element?(view, "#niche-advice-competition", "I haven't checked who is on Google's first page")
    assert has_element?(view, "#niche-stat-competitors [data-part=value]", "—")
  end

  test "a Niche whose page failed offers the choice again instead of a link to the page", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("6.0"), status: :chosen)
    insert(:page, run: run, niche: niche, status: :failed, brief: nil)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    refute has_element?(view, "#open-page")
    assert has_element?(view, "#choose-niche")
  end

  test "a Niche with direct competitors on Google's first page offers to check their prices and says it costs", %{
    conn: conn
  } do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))
    checked = phrase_in_niche(run, niche, %{volume: 100, cpc: nil})
    insert(:serp_assessment, run: run, phrase: checked.phrase, labels: labels(%{"direct_competitor" => 2, "blog" => 8}))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#competitor-prices h3", "Competitor prices")
    assert has_element?(view, "#check-prices-note", "up to 5 businesses like yours")
    assert has_element?(view, "#check-prices-note", "API cost")
    assert has_element?(view, "#check-prices", "Check competitor prices")
    refute has_element?(view, "#competitor-prices-none")

    view |> element("#check-prices") |> render_click()

    price_check = Repo.get_by!(PriceCheck, cluster_id: niche.id)
    assert_enqueued(worker: CheckCompetitorPrices, args: %{price_check_id: price_check.id})

    assert has_element?(
             view,
             "#competitor-prices-status",
             "I'm reading competitor pages and looking for prices: 0 of 2 pages done."
           )

    refute has_element?(view, "#check-prices")
  end

  test "a Niche without direct competitors on Google's first page says there is nobody to check", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))
    checked = phrase_in_niche(run, niche, %{volume: 100, cpc: nil})
    insert(:serp_assessment, run: run, phrase: checked.phrase, labels: labels(%{"blog" => 10}))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(
             view,
             "#competitor-prices-none",
             "No business like yours is on Google's first page for these searches"
           )

    refute has_element?(view, "#check-prices")
  end

  test "a finished check lists each competitor's page with its prices as written, or why there are none", %{
    conn: conn
  } do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))
    price_check = insert(:price_check, run: run, niche: niche, status: :done)

    found =
      insert(:competitor_page,
        price_check: price_check,
        google_position: 1,
        domain: "lodowisko-a.example",
        url: "https://lodowisko-a.example/",
        read_url: "https://lodowisko-a.example/cennik",
        outcome: :prices_found,
        offers: [
          %CompetitorOffer{name: "Wypożyczenie łyżew", price: "15 zł / h", quote: "Wypożyczenie łyżew 15 zł / h"},
          %CompetitorOffer{name: "Ostrzenie", price: "od 20,00 PLN", quote: "Ostrzenie od 20,00 PLN"}
        ]
      )

    no_prices =
      insert(:competitor_page,
        price_check: price_check,
        google_position: 2,
        read_url: "https://lodowisko-b.example/",
        outcome: :no_prices
      )

    unreadable = insert(:competitor_page, price_check: price_check, google_position: 3, outcome: :unreadable)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(
             view,
             ~s(#competitor-page-#{found.id} a[data-part=domain][href="https://lodowisko-a.example/cennik"][target=_blank][rel="noopener noreferrer"]),
             "lodowisko-a.example"
           )

    assert has_element?(view, "#competitor-page-#{found.id} [data-part=offer]", "Wypożyczenie łyżew: 15 zł / h")
    assert has_element?(view, "#competitor-page-#{found.id} [data-part=offer]", "Ostrzenie: od 20,00 PLN")
    assert has_element?(view, ~s(#competitor-page-#{no_prices.id} a[href="https://lodowisko-b.example/"]))

    assert has_element?(
             view,
             "#competitor-page-#{no_prices.id} [data-part=no-prices]",
             "I found no prices on this page"
           )

    assert has_element?(view, ~s(#competitor-page-#{unreadable.id} a[href="#{unreadable.url}"]), unreadable.domain)

    assert has_element?(
             view,
             "#competitor-page-#{unreadable.id} [data-part=unreadable]",
             "This page could not be opened"
           )

    assert has_element?(view, "#competitor-prices-source")
    refute has_element?(view, "#check-prices")
    refute has_element?(view, "#competitor-prices-status")
  end

  test "the prices appear when the check finishes, without reloading", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))
    checked = phrase_in_niche(run, niche, %{volume: 100, cpc: nil})
    insert(:serp_assessment, run: run, phrase: checked.phrase, labels: labels(%{"direct_competitor" => 1, "blog" => 9}))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")
    view |> element("#check-prices") |> render_click()

    Mox.stub(Dirmoon.WebPageMock, :fetch, fn url ->
      {:ok, %{url: url, status: 200, redirects: [], content_type: "text/html", body: "<p>Doba 80 zł</p>"}}
    end)

    Mox.stub(Dirmoon.LLMMock, :structured, fn _request ->
      {:ok, %{"offers" => [%{"name" => "Doba", "price" => "80 zł", "quote" => "Doba 80 zł"}]}, Decimal.new("0.001")}
    end)

    price_check = Repo.get_by!(PriceCheck, cluster_id: niche.id)
    assert :ok = perform_job(CheckCompetitorPrices, %{price_check_id: price_check.id})

    assert has_element?(view, "#competitor-prices-list [data-part=offer]", "Doba: 80 zł")
    refute has_element?(view, "#competitor-prices-status")
  end

  test "a failed check says why and offers to check again", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))
    price_check = insert(:price_check, run: run, niche: niche, status: :failed, error: "No OpenAI API key")
    insert(:competitor_page, price_check: price_check)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(
             view,
             "#competitor-prices-error.text-warn",
             "I couldn't check the prices: No OpenAI API key"
           )

    refute has_element?(view, "#competitor-prices-list")

    view |> element("#check-prices") |> render_click()

    assert_enqueued(worker: CheckCompetitorPrices, args: %{price_check_id: price_check.id})
    assert has_element?(view, "#competitor-prices-status", "0 of 1 page done")
  end

  test "asking for prices of a Niche whose competitors are gone meanwhile says there is nobody to check", %{
    conn: conn
  } do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))
    checked = phrase_in_niche(run, niche, %{volume: 100, cpc: nil})

    assessment =
      insert(:serp_assessment, run: run, phrase: checked.phrase, labels: labels(%{"direct_competitor" => 1, "blog" => 9}))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")
    Repo.delete!(assessment)

    view |> element("#check-prices") |> render_click()

    assert has_element?(view, "#flash-error", "so I have no prices to check")
    assert has_element?(view, "#competitor-prices-none")
    refute_enqueued(worker: CheckCompetitorPrices)
  end

  test "asking for prices of a Niche deleted meanwhile says it is not found", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))
    checked = phrase_in_niche(run, niche, %{volume: 100, cpc: nil})
    insert(:serp_assessment, run: run, phrase: checked.phrase, labels: labels(%{"direct_competitor" => 1, "blog" => 9}))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")
    Repo.delete!(niche)

    view |> element("#check-prices") |> render_click()

    assert has_element?(view, "#flash-error", "Topic not found")
  end

  test "asking for prices while the results are being redone waits for them", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))
    checked = phrase_in_niche(run, niche, %{volume: 100, cpc: nil})
    insert(:serp_assessment, run: run, phrase: checked.phrase, labels: labels(%{"direct_competitor" => 1, "blog" => 9}))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")
    RunStep |> Repo.get_by!(run_id: run.id, number: 7) |> Ecto.Changeset.change(status: :running) |> Repo.update!()

    view |> element("#check-prices") |> render_click()

    assert has_element?(view, "#flash-error", "I'll check prices when the results are ready")
    refute_enqueued(worker: CheckCompetitorPrices)
  end

  test "asking for prices with no Niche selected does nothing", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    render_hook(view, "check_prices", %{})

    refute has_element?(view, "#competitor-prices")
    refute_enqueued(worker: CheckCompetitorPrices)
  end

  test "an Existing Site's Price Check compares my matched page with each competitor's page, with the sites linking to each",
       %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    %{run: run, niche: niche} = existing_site_niche(scope)

    site_scan =
      insert(:site_scan,
        run: run,
        status: :done,
        facts: %{"matching" => %{"done" => true}, "linking_sites" => %{"checked" => true, "count" => 1_250}}
      )

    my_page =
      insert(:scanned_page,
        site_scan: site_scan,
        url: "https://strona-testowa.pl/hotel",
        cluster_id: niche.id,
        facts: %{
          "word_count" => 420,
          "main_headings" => ["Hotel dla psów"],
          "sub_headings" => [%{"level" => 2, "text" => "Cennik"}],
          "structured_data_types" => [],
          "ways_to_act" => %{"phone_links" => 0, "email_links" => 0, "forms" => 0, "button_links" => 1}
        }
      )

    price_check = insert(:price_check, run: run, niche: niche, status: :done)

    competitor =
      insert(:competitor_page,
        price_check: price_check,
        domain: "hotel-a.example",
        url: "https://hotel-a.example/",
        read_url: "https://hotel-a.example/cennik",
        outcome: :prices_found,
        linking_sites: 31,
        facts: comparison_facts(%{"word_count" => 1_900, "structured_data_types" => ["LocalBusiness", "Offer"]})
      )

    without_prices =
      insert(:competitor_page,
        price_check: price_check,
        domain: "hotel-b.example",
        outcome: :no_prices,
        facts: comparison_facts(%{"ways_to_act" => %{"phone_links" => 0, "email_links" => 0, "forms" => 0}})
      )

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#page-comparison h3", "Your page against theirs")
    assert has_element?(view, "#page-comparison-site[data-state=page] th", "Your page")

    assert has_element?(
             view,
             ~s(#page-comparison-site a[data-part=address][href="#{my_page.url}"][target=_blank][rel="noopener noreferrer nofollow"])
           )

    assert has_element?(view, "#page-comparison-site [data-part=words]", "420")
    assert has_element?(view, "#page-comparison-site [data-part=headings]", "1 main, 1 smaller")
    assert has_element?(view, "#page-comparison-site [data-part=structured-data]", "No")
    assert has_element?(view, "#page-comparison-site [data-part=states-price]", "—")
    assert has_element?(view, "#page-comparison-site [data-part=contact]", "None")
    assert has_element?(view, "#page-comparison-site [data-part=linking-sites]", "1,250")
    refute has_element?(view, "#page-comparison-site [data-part=note]")

    row = "#page-comparison-competitor-#{competitor.id}"

    assert has_element?(
             view,
             ~s(#{row} a[data-part=domain][href="https://hotel-a.example/cennik"][rel="noopener noreferrer nofollow"]),
             "hotel-a.example"
           )

    assert has_element?(view, "#{row} [data-part=words]", "1,900")
    assert has_element?(view, "#{row} [data-part=headings]", "1 main, 4 smaller")
    assert has_element?(view, "#{row} [data-part=structured-data]", "Yes")
    assert has_element?(view, ~s(#{row} [data-part=structured-data] [title="LocalBusiness, Offer"]))
    assert has_element?(view, "#{row} [data-part=types]", "LocalBusiness, Offer")
    assert has_element?(view, "#{row} [data-part=states-price]", "Yes")
    assert has_element?(view, "#{row} [data-part=contact]", "Phone, e-mail, form")
    assert has_element?(view, "#{row} [data-part=linking-sites]", "31")

    other = "#page-comparison-competitor-#{without_prices.id}"
    assert has_element?(view, "#{other} [data-part=states-price]", "No")
    assert has_element?(view, "#{other} [data-part=contact]", "None")
    assert has_element?(view, "#{other} [data-part=linking-sites]", "—")

    assert has_element?(view, "#page-comparison-legend dt", "Structured data")

    assert has_element?(
             view,
             "#page-comparison-legend dd",
             "Labels in the page code that tell Google your name, address and prices."
           )

    assert has_element?(view, "#page-comparison-legend dd", "third-party index of links, so it is approximate")
  end

  test "the comparison scrolls inside its own box on a narrow screen", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    %{run: run, niche: niche} = existing_site_niche(scope)
    insert(:site_scan, run: run, status: :done, facts: %{"matching" => %{"done" => true}})
    read_competitor_page(run, niche)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#page-comparison > div.overflow-x-auto > table.w-full")
    assert has_element?(view, "#page-comparison-legend.grid")
  end

  test "a topic I have no page for says so in my row, with a nudge to its brief", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    %{run: run, niche: niche} = existing_site_niche(scope)

    insert(:site_scan,
      run: run,
      status: :done,
      facts: %{"matching" => %{"done" => true}, "linking_sites" => %{"checked" => true, "count" => 0}}
    )

    read_competitor_page(run, niche)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(
             view,
             "#page-comparison-site[data-state=no_page] [data-part=message]",
             "You have no page for this topic yet. Choose this topic below and the brief I write"
           )

    assert has_element?(view, "#page-comparison-site [data-part=linking-sites]", "0")
    refute has_element?(view, "#page-comparison-site [data-part=words]")
  end

  test "my row says why there is nothing of mine to compare yet", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})

    for {scan, state, message} <- [
          {nil, "no_scan", "I haven't read your site"},
          {%{status: :scanning, facts: %{}}, "scanning", "I'm still reading your site."},
          {%{status: :failed, facts: %{}}, "failed", "I couldn't read your site"},
          {%{status: :done, facts: %{}}, "not_matched", "I haven't matched your pages to the topics yet."},
          {%{status: :done, facts: %{"matching" => %{"done" => false, "reason" => "failed"}}}, "not_matched",
           "I haven't matched"}
        ] do
      %{run: run, niche: niche} = existing_site_niche(scope)
      if scan, do: insert(:site_scan, Map.put(scan, :run, run))
      read_competitor_page(run, niche)

      {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

      assert has_element?(view, "#page-comparison-site[data-state=#{state}] [data-part=message]", message)
      assert has_element?(view, "#page-comparison-site [data-part=linking-sites]", "—")
    end
  end

  test "my row follows the scan: once my pages are read and matched it shows my page, without reloading", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    %{run: run, niche: niche} = existing_site_niche(scope)
    site_scan = insert(:site_scan, run: run, status: :scanning, facts: %{})
    read_competitor_page(run, niche)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")
    assert has_element?(view, "#page-comparison-site[data-state=scanning]")

    insert(:scanned_page, site_scan: site_scan, cluster_id: niche.id, facts: %{"word_count" => 300})

    site_scan
    |> Ecto.Changeset.change(status: :done, facts: %{"matching" => %{"done" => true}})
    |> Repo.update!()
    |> SiteScans.broadcast_updated()

    assert has_element?(view, "#page-comparison-site[data-state=page] [data-part=words]", "300")
  end

  test "with several pages of mine for a topic, my row shows the first one read and says it is 1 of them", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    %{run: run, niche: niche} = existing_site_niche(scope)
    site_scan = insert(:site_scan, run: run, status: :done, facts: %{"matching" => %{"done" => true}})

    insert(:scanned_page,
      site_scan: site_scan,
      position: 2,
      url: "https://strona-testowa.pl/druga",
      cluster_id: niche.id,
      facts: %{"word_count" => 90}
    )

    insert(:scanned_page,
      site_scan: site_scan,
      position: 1,
      url: "https://strona-testowa.pl/pierwsza",
      cluster_id: niche.id,
      facts: %{"word_count" => 300}
    )

    read_competitor_page(run, niche)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#page-comparison-site [data-part=address]", "https://strona-testowa.pl/pierwsza")
    assert has_element?(view, "#page-comparison-site [data-part=note]", "1 of 2 pages about this topic")
    assert has_element?(view, "#page-comparison-site [data-part=words]", "300")
    assert has_element?(view, "#page-comparison-site [data-part=headings]", "—")
  end

  test "addresses that are not web addresses are shown as text in the comparison, never as links", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    %{run: run, niche: niche} = existing_site_niche(scope)
    site_scan = insert(:site_scan, run: run, status: :done, facts: %{"matching" => %{"done" => true}})

    insert(:scanned_page,
      site_scan: site_scan,
      url: "javascript:alert(1)",
      cluster_id: niche.id,
      facts: %{"word_count" => 300}
    )

    price_check = insert(:price_check, run: run, niche: niche, status: :done)

    competitor =
      insert(:competitor_page,
        price_check: price_check,
        url: "javascript:alert(2)",
        read_url: nil,
        outcome: :unreadable
      )

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#page-comparison-site span[data-part=address]", "javascript:alert(1)")
    refute has_element?(view, "#page-comparison-site a")

    row = "#page-comparison-competitor-#{competitor.id}"
    assert has_element?(view, "#{row} span[data-part=domain]", competitor.domain)
    refute has_element?(view, "#{row} a")
    refute has_element?(view, "#competitor-page-#{competitor.id} a")
    assert has_element?(view, "#competitor-page-#{competitor.id} span[data-part=domain]", competitor.domain)
    assert has_element?(view, "#{row} [data-part=note]", "This page could not be opened")
    assert has_element?(view, "#{row} [data-part=words]", "—")
    assert has_element?(view, "#{row} [data-part=structured-data]", "—")
    assert has_element?(view, "#{row} [data-part=states-price]", "—")
    assert has_element?(view, "#{row} [data-part=contact]", "—")
  end

  test "there is no comparison before the Price Check has read a page, nor for a New Idea", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    %{run: run, niche: niche} = existing_site_niche(scope)
    insert(:site_scan, run: run, status: :done, facts: %{"matching" => %{"done" => true}})

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")
    refute has_element?(view, "#page-comparison")

    price_check = insert(:price_check, run: run, niche: niche, status: :checking)
    insert(:competitor_page, price_check: price_check, outcome: :waiting)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")
    refute has_element?(view, "#page-comparison")

    new_idea = scored_run(scope)
    new_idea_niche = insert(:niche, run: new_idea, score: Decimal.new("6.0"))
    read_competitor_page(new_idea, new_idea_niche)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{new_idea}/results")
    assert has_element?(view, "#competitor-prices-list")
    refute has_element?(view, "#page-comparison")
  end

  test "for an Existing Site the Price Check button says it also compares the pages and counts the linking sites' request",
       %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope, %{mode: :existing_site, domain: "strona-testowa.pl"})
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))
    checked = phrase_in_niche(run, niche, %{volume: 100, cpc: nil})
    insert(:serp_assessment, run: run, phrase: checked.phrase, labels: labels(%{"direct_competitor" => 2, "blog" => 8}))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#check-prices", "Check competitor prices and pages")
    assert has_element?(view, "#check-prices-note", "compare their pages with yours")
    assert has_element?(view, "#check-prices-note", "counting the sites that link to them is one more request")
  end

  test "at the research's brief cap a topic that has a brief still links to it", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    insert_list(Billing.offer().briefs_per_research - 1, :page, run: run, status: :ready)
    niche = insert(:niche, run: run, score: Decimal.new("6.0"), status: :chosen)
    page = insert(:page, run: run, niche: niche, status: :ready)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?niche=#{niche.id}")

    assert has_element?(view, "#open-page[href='/app/pages/#{page.id}']", "Open brief")
  end

  test "choosing a topic once the research's briefs are used starts nothing and says so", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    briefs = Billing.offer().briefs_per_research
    insert_list(briefs, :page, run: run, status: :ready)
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?niche=#{niche.id}")
    view |> element("#choose-niche") |> render_click()

    assert has_element?(view, "#flash-error", "This research's #{briefs} briefs are used, so I can't write another")
    assert Repo.get_by(Page, cluster_id: niche.id) == nil
    assert Repo.get!(Niche, niche.id).status == :proposed
    refute_enqueued(worker: WriteBrief)
  end

  test "at the research's price check cap a topic's failed check still runs again", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    insert_list(Billing.offer().price_checks_per_research - 1, :price_check, run: run, status: :done)
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))
    price_check = insert(:price_check, run: run, niche: niche, status: :failed, error: "No OpenAI API key")
    insert(:competitor_page, price_check: price_check)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?niche=#{niche.id}")
    view |> element("#check-prices") |> render_click()

    assert_enqueued(worker: CheckCompetitorPrices, args: %{price_check_id: price_check.id})
    assert has_element?(view, "#competitor-prices-status", "0 of 1 page done")
  end

  test "asking for prices once the research's price checks are used starts nothing and says so", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    price_checks = Billing.offer().price_checks_per_research
    insert_list(price_checks, :price_check, run: run, status: :done)
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))
    checked = phrase_in_niche(run, niche, %{volume: 100, cpc: nil})
    insert(:serp_assessment, run: run, phrase: checked.phrase, labels: labels(%{"direct_competitor" => 1, "blog" => 9}))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?niche=#{niche.id}")
    view |> element("#check-prices") |> render_click()

    assert has_element?(
             view,
             "#flash-error",
             "This research's #{price_checks} competitor price checks are used, so I can't check another topic"
           )

    assert Repo.get_by(PriceCheck, cluster_id: niche.id) == nil
    refute_enqueued(worker: CheckCompetitorPrices)
  end

  test "an Account with no research left still opens a past run's results", %{conn: conn} do
    account = insert(:account, unpaid_access: false)
    user = insert(:user, memberships: [%Membership{account: account}])
    conn = log_in_user(conn, user)
    run = scored_run(%{account: account})
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#app-main #results #niches #niche-row-#{niche.id}")
  end

  defp scored_run(%{account: account}, attrs \\ %{}) do
    steps = build_run_steps(Map.new(1..7, &{&1, :done}))
    insert(:run, Map.merge(%{account: account, status: :awaiting_choice, steps: steps}, attrs))
  end

  defp existing_site_niche(scope) do
    run = scored_run(scope, %{mode: :existing_site, domain: "strona-testowa.pl"})
    %{run: run, niche: insert(:niche, run: run, score: Decimal.new("6.0"))}
  end

  defp read_competitor_page(run, niche) do
    price_check = insert(:price_check, run: run, niche: niche, status: :done)
    insert(:competitor_page, price_check: price_check, outcome: :no_prices, facts: comparison_facts(%{}))
  end

  defp comparison_facts(facts) do
    Map.merge(
      %{
        "word_count" => 800,
        "main_heading_count" => 1,
        "sub_heading_count" => 4,
        "structured_data_types" => [],
        "images" => 3,
        "title_length" => 40,
        "ways_to_act" => %{"phone_links" => 2, "email_links" => 1, "forms" => 1, "button_links" => 0}
      },
      facts
    )
  end

  defp phrase_in_niche(run, niche, metrics) do
    phrase = insert(:phrase, phrase: unique_phrase_text("fraza wyników"))

    insert(:metrics,
      phrase: phrase,
      location_code: run.location_code,
      search_volume: metrics.volume,
      cpc: metrics.cpc && Decimal.new(metrics.cpc)
    )

    insert(:run_phrase, run: run, phrase: phrase, niche: niche)
  end

  defp labels(counts_by_page_type) do
    counts_by_page_type
    |> Enum.flat_map(fn {page_type, count} -> List.duplicate(page_type, count) end)
    |> Enum.with_index(1)
    |> Enum.map(fn {page_type, position} -> %{"position" => position, "page_type" => page_type} end)
  end
end
