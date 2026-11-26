defmodule DirmoonWeb.SiteScanLiveTest do
  use DirmoonWeb.ConnCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  import Phoenix.LiveViewTest

  alias Dirmoon.Repo
  alias Dirmoon.SiteScans
  alias Dirmoon.Workers.ScanSite

  test "a finished scan shows its Findings under plain questions, the topics people search for first", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    site_scan = scan(scope, %{status: :done, pages_read: 1, facts: %{"https" => false, "sitemap" => sitemap(true)}})
    home_page(site_scan)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{site_scan.run}/site")

    assert has_element?(view, "#app-nav #nav-runs[aria-current=page]")
    assert has_element?(view, "#site-scan-status-line", "I read 1 page of #{site_scan.run.domain} and found")
    assert has_element?(view, "#question-niche_coverage h2", "Does your site cover what people search for?")
    assert has_element?(view, "#question-findable h2", "Can Google find and read your site?")
    assert has_element?(view, "#question-page_content h2", "Does each page say what it is about?")
    assert has_element?(view, "#question-visitor h2", "Does it work for a visitor on a phone?")
    assert has_element?(view, "#question-business h2", "Does it look like a real business to Google?")

    assert section_ids(view) == [
             "question-niche_coverage",
             "question-findable",
             "question-page_content",
             "question-visitor",
             "question-business"
           ]
  end

  test "an international site is named in its Unicode form", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, mode: :existing_site, domain: "xn--w-uga1v8h.pl")
    scanning = insert(:site_scan, run: run, status: :scanning, pages_read: 2)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/site")

    assert has_element?(view, "h1", "Your site: żółw.pl")
    assert has_element?(view, "#site-scan-progress", "I'm reading żółw.pl: 2 pages so far.")

    scanning
    |> Ecto.Changeset.change(status: :done, pages_read: 1, facts: %{"sitemap" => sitemap(true)})
    |> Repo.update!()

    SiteScans.broadcast_updated(scanning)

    assert has_element?(view, "#site-scan-status-line", "I read 1 page of żółw.pl and found")
  end

  test "a site whose domain was stored in its Unicode form is named as stored", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, mode: :existing_site, domain: "żółw.pl")
    insert(:site_scan, run: run, status: :scanning, pages_read: 2)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/site")

    assert has_element?(view, "h1", "Your site: żółw.pl")
    assert has_element?(view, "#site-scan-progress", "I'm reading żółw.pl: 2 pages so far.")
  end

  test "within a question problems come first and the good news is folded under what's fine", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    site_scan = scan(scope, %{status: :done, facts: %{"https" => false, "sitemap" => sitemap(true)}})

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{site_scan.run}/site")

    assert has_element?(view, "#question-findable > #finding-https[data-level=problem] [data-part=level]", "Fix this")
    assert has_element?(view, "#finding-https [data-part=meaning]", "What it means:")
    assert has_element?(view, "#finding-https [data-part=action]", "What to do:")
    assert has_element?(view, "#question-findable-fine summary", "What's fine (1)")
    assert has_element?(view, "#question-findable-fine #finding-sitemap[data-level=good] [data-part=level]", "Fine")
    refute has_element?(view, "#finding-sitemap [data-part=action]")
  end

  test "the summary counts the Findings at each level", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})

    site_scan =
      scan(scope, %{
        status: :done,
        facts: %{"https" => false, "sitemap" => sitemap(false), "indexed_pages" => not_checked("not_configured")}
      })

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{site_scan.run}/site")

    assert has_element?(view, "#site-scan-summary-problem dd", "1")
    assert has_element?(view, "#site-scan-summary-warning dd", "1")
    assert has_element?(view, "#site-scan-summary-not_checked dd", "2")
    assert has_element?(view, "#site-scan-summary-good dd", "0")
    assert has_element?(view, "#finding-indexed_pages[data-level=not_checked] [data-part=level]", "Not checked")
    assert has_element?(view, "#finding-sitemap[data-level=warning] [data-part=level]", "Worth improving")
  end

  test "a finished scan says in plain words how many other sites link to mine", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})

    site_scan =
      scan(scope, %{status: :done, pages_read: 1, facts: %{"linking_sites" => %{"checked" => true, "count" => 17}}})

    home_page(site_scan)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{site_scan.run}/site")

    assert has_element?(
             view,
             "#question-business-fine #finding-linking_sites[data-level=good] [data-part=title]",
             "17 other sites link to yours."
           )

    assert has_element?(view, "#finding-linking_sites [data-part=meaning]", "approximate")
  end

  test "a finished scan with nothing to fix says so", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    site_scan = scan(scope, %{status: :done, pages_read: 2, facts: %{"https" => true}})

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{site_scan.run}/site")

    assert has_element?(
             view,
             "#site-scan-status-line",
             "I read 2 pages of #{site_scan.run.domain} and found nothing to fix."
           )

    assert has_element?(view, "#question-visitor-empty", "I have nothing to say about this.")
  end

  test "the pages a Finding concerns are listed as links that open in a new tab, the rest counted", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    blocked = for number <- 1..25, do: "https://strona-testowa.example/ukryta-#{number}"
    site_scan = scan(scope, %{status: :done, facts: %{"blocked_pages" => blocked}})

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{site_scan.run}/site")

    assert has_element?(view, "#finding-blocked_pages-pages summary", "Show the 25 pages")
    assert has_element?(view, "#finding-blocked_pages-pages [data-part=more]", "and 5 more")

    assert has_element?(
             view,
             ~s(#finding-blocked_pages-pages a[href="#{hd(blocked)}"][target=_blank][rel="noopener noreferrer nofollow"])
           )
  end

  test "an address that is not a web address is shown as text, never as a link", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    site_scan = scan(scope, %{status: :done, facts: %{"blocked_pages" => ["javascript:alert(1)"]}})

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{site_scan.run}/site")

    assert has_element?(view, "#finding-blocked_pages-pages summary", "Show the page")
    assert has_element?(view, "#finding-blocked_pages-pages [data-part=page] span", "javascript:alert(1)")
    refute has_element?(view, "#finding-blocked_pages-pages a")
    refute has_element?(view, "#finding-blocked_pages-pages [data-part=more]")
  end

  test "topics worth going after with no page are listed, each leading to its topic in the results", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    site_scan = scan(scope, %{status: :done, facts: %{"matching" => %{"done" => true, "pages" => 1, "matched" => 0}}})
    niche = insert(:niche, run: site_scan.run, score: Decimal.new("6"))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{site_scan.run}/site")

    assert has_element?(view, "#finding-niches_without_page[data-level=problem]")
    assert has_element?(view, "#finding-niches_without_page-niches summary", "Show the topic")

    assert has_element?(
             view,
             ~s(#finding-niches_without_page-niches a[href="/app/runs/#{site_scan.run_id}/results?niche=#{niche.id}&view=niches"]),
             niche.name
           )

    assert has_element?(view, "#finding-niches_without_page-niches [data-part=niche]", "typed 0 times a month")
  end

  test "topics with two pages list each topic with its pages", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    site_scan = scan(scope, %{status: :done, facts: %{"matching" => %{"done" => true, "pages" => 2, "matched" => 2}}})
    niche = insert(:niche, run: site_scan.run, score: Decimal.new("6"))
    first = insert(:scanned_page, site_scan: site_scan, cluster_id: niche.id, facts: %{"word_count" => 300})
    insert(:scanned_page, site_scan: site_scan, cluster_id: niche.id, facts: %{"word_count" => 300})

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{site_scan.run}/site")

    assert has_element?(view, "#finding-several_pages_for_one_niche-niches [data-part=niche]", niche.name)
    assert has_element?(view, ~s(#finding-several_pages_for_one_niche-niches a[href="#{first.url}"]))
    refute has_element?(view, "#finding-several_pages_for_one_niche-niches [data-part=niche] .text-xs")
  end

  test "searches close to the first page are listed with their position and the page that shows up", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    site_scan = scan(scope, %{status: :done})
    page_url = "https://#{site_scan.run.domain}/cennik"

    run_phrase =
      insert(:run_phrase, run: site_scan.run, current_position: Decimal.new("12"), current_position_url: page_url)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{site_scan.run}/site")

    assert has_element?(view, "#finding-close_to_first_page-phrases summary", "Show the search")
    assert has_element?(view, "#finding-close_to_first_page-phrases [data-part=phrase]", run_phrase.phrase.phrase)
    assert has_element?(view, "#finding-close_to_first_page-phrases [data-part=phrase]", "position 12")
    assert has_element?(view, ~s(#finding-close_to_first_page-phrases a[href="#{page_url}"]))
  end

  test "long lists of topics and searches show the first ones and count the rest", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    site_scan = scan(scope, %{status: :done, facts: %{"matching" => %{"done" => true, "pages" => 0, "matched" => 0}}})

    for _number <- 1..25 do
      insert(:niche, run: site_scan.run, score: Decimal.new("6"))
      insert(:run_phrase, run: site_scan.run, current_position: Decimal.new("15"))
    end

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{site_scan.run}/site")

    assert has_element?(view, "#finding-niches_without_page-niches summary", "Show the 25 topics")
    assert has_element?(view, "#finding-niches_without_page-niches [data-part=more]", "and 5 more")
    assert has_element?(view, "#finding-close_to_first_page-phrases summary", "Show the 25 searches")
    assert has_element?(view, "#finding-close_to_first_page-phrases [data-part=more]", "and 5 more")
  end

  test "a check that gives several Findings numbers each one", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})

    speed = %{
      "checked" => true,
      "phone_checks" => [
        %{"id" => "meta-viewport", "passed" => false},
        %{"id" => "target-size", "passed" => false},
        %{"id" => "viewport-insight", "passed" => true}
      ]
    }

    site_scan = scan(scope, %{status: :done, facts: %{"speed" => speed}})

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{site_scan.run}/site")

    assert has_element?(view, "#finding-phone_usability-1", "isn't set up for phone screens")
    assert has_element?(view, "#finding-phone_usability-2", "hard to tap")
    assert has_element?(view, "#question-visitor-fine #finding-phone_usability-3")
  end

  test "while the scan reads the site I see how many pages are read, and it updates without a reload", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    site_scan = scan(scope, %{status: :scanning, pages_read: 2})

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{site_scan.run}/site")

    assert has_element?(view, "#site-scan-progress", "I'm reading #{site_scan.run.domain}: 2 pages so far.")
    assert has_element?(view, "#site-scan-status-line", "I'm reading #{site_scan.run.domain}: 2 pages so far.")
    assert has_element?(view, "#site-scan-progress", "The checks appear here once I've read the site.")
    refute has_element?(view, "#question-page_content")
    refute has_element?(view, "#retry-site-scan")

    site_scan |> Ecto.Changeset.change(pages_read: 7) |> Repo.update!() |> SiteScans.broadcast_updated()

    assert has_element?(view, "#site-scan-progress", "7 pages so far.")
  end

  test "when the scan ends, its Findings appear without a reload", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    site_scan = scan(scope, %{status: :scanning, pages_read: 1, facts: %{"https" => false}})
    home_page(site_scan)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{site_scan.run}/site")

    refute has_element?(view, "#finding-https")
    refute has_element?(view, "#site-scan-summary")

    site_scan |> Ecto.Changeset.change(pages_read: 2) |> Repo.update!() |> SiteScans.broadcast_updated()

    refute has_element?(view, "#finding-https")
    assert has_element?(view, "#site-scan-progress", "2 pages so far.")

    site_scan |> Repo.reload!() |> SiteScans.finish(:done)

    assert has_element?(view, "#finding-https[data-level=problem]")
    refute has_element?(view, "#site-scan-progress")
  end

  test "a long address wraps on a narrow screen instead of running off it", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    site_scan = scan(scope, %{status: :failed, error: "The site could not be opened"})

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{site_scan.run}/site")

    assert has_element?(view, "#app-status span.break-words.min-w-0 #site-scan-status-line")
    assert has_element?(view, "#site-scan-failed > span.break-words.min-w-0", site_scan.run.domain)

    site_scan |> Ecto.Changeset.change(status: :scanning) |> Repo.update!() |> SiteScans.broadcast_updated()

    assert has_element?(view, "#site-scan-progress > span.break-words.min-w-0", site_scan.run.domain)
  end

  test "a run id beyond the database's id range sends the User back to the runs list", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})

    assert {:error, {:live_redirect, %{to: "/app/runs", flash: flash}}} =
             live(conn, "/app/runs/99999999999999999999999/site")

    assert flash["error"] == "Research not found"
  end

  test "a failed scan shows why, and the button runs it again", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    reason = "The site could not be opened: none of its addresses answered with a page"
    site_scan = scan(scope, %{status: :failed, error: reason})

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{site_scan.run}/site")

    assert has_element?(view, "#site-scan-status-line", "I couldn't read #{site_scan.run.domain}.")
    assert has_element?(view, "#site-scan-failed #site-scan-error", reason)

    view |> element("#retry-site-scan") |> render_click()

    assert_enqueued(worker: ScanSite, args: %{site_scan_id: site_scan.id})
    assert has_element?(view, "#site-scan-progress")
    refute has_element?(view, "#site-scan-failed")
  end

  test "a scan whose reading stopped part-way says it stopped on my side, and the button picks it up", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    long_ago = DateTime.shift(DateTime.utc_now(:second), hour: -3)
    site_scan = scan(scope, %{status: :scanning, pages_read: 4, updated_at: long_ago})

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{site_scan.run}/site")

    assert has_element?(view, "#site-scan-failed", "My reading of your site stopped part-way.")
    assert has_element?(view, "#site-scan-status-line", "stopped part-way, after 4 pages. I can pick it up")
    refute has_element?(view, "#site-scan-progress")

    view |> element("#retry-site-scan") |> render_click()

    assert_enqueued(worker: ScanSite, args: %{site_scan_id: site_scan.id})
    refute has_element?(view, "#site-scan-failed")
  end

  test "a research without a site says it has none", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/site")

    assert has_element?(view, "#site-scan-empty", "This research has no site.")
    assert has_element?(view, "#site-scan-status-line", "This research has no site to read.")
    assert has_element?(view, ~s(#site-scan-results-link[href="/app/runs/#{run.id}/results"]))
    refute has_element?(view, "#site-scan-summary")
  end

  test "another Account's run sends the User back to the runs list", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    site_scan = insert(:site_scan)

    assert {:error, {:live_redirect, %{to: "/app/runs", flash: flash}}} = live(conn, ~p"/app/runs/#{site_scan.run}/site")
    assert flash["error"] == "Research not found"
  end

  test "a signed-out visitor is sent to sign in", %{conn: conn} do
    site_scan = insert(:site_scan)

    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/app/runs/#{site_scan.run}/site")
  end

  test "a research deleted while its screen is open sends the User back to the runs list", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    site_scan = scan(scope, %{status: :scanning})
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{site_scan.run}/site")

    Repo.delete!(site_scan.run)
    SiteScans.broadcast_updated(site_scan)

    assert_redirect(view, "/app/runs")
  end

  test "running again the scan of a research deleted meanwhile sends the User back to the runs list", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    site_scan = scan(scope, %{status: :failed, error: "The site could not be opened"})
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{site_scan.run}/site")

    Repo.delete!(site_scan.run)
    view |> element("#retry-site-scan") |> render_click()

    assert_redirect(view, "/app/runs")
  end

  defp scan(%{account: account}, attrs) do
    run =
      insert(:run,
        account: account,
        mode: :existing_site,
        domain: ExMachina.sequence(:site_scan_live_domain, &"strona-#{&1}.example")
      )

    insert(:site_scan, Map.merge(%{run: run}, attrs))
  end

  defp home_page(site_scan) do
    insert(:scanned_page, site_scan: site_scan, url: "https://#{site_scan.run.domain}/", facts: %{"word_count" => 300})
  end

  defp sitemap(found), do: %{"found" => found, "url" => nil, "page_count" => 0}

  defp not_checked(reason), do: %{"checked" => false, "reason" => reason}

  defp section_ids(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#site-scan > section")
    |> LazyHTML.attribute("id")
  end
end
