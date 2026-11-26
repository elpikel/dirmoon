defmodule Dirmoon.SiteScansTest do
  use Dirmoon.DataCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  alias Dirmoon.Accounts.Account
  alias Dirmoon.Accounts.Scope
  alias Dirmoon.Niches.Niche
  alias Dirmoon.Research.Run
  alias Dirmoon.SiteScans
  alias Dirmoon.SiteScans.Finding
  alias Dirmoon.SiteScans.ScannedPage
  alias Dirmoon.SiteScans.SiteScan
  alias Dirmoon.Workers.ScanSite

  test "starting the scan of an Existing Site run stores it scanning with nothing read yet" do
    run = insert(:run, mode: :existing_site, domain: "kancelaria-testowa.example")

    assert {:ok, %SiteScan{id: site_scan_id}} = SiteScans.start(run)

    assert %SiteScan{status: :scanning, error: nil, facts: %{}, pages_read: 0, run_id: run_id} =
             Repo.get!(SiteScan, site_scan_id)

    assert run_id == run.id
  end

  test "starting the scan of an Existing Site run enqueues its job on the site scan queue" do
    run = insert(:run, mode: :existing_site, domain: "kancelaria-testowa.example")

    {:ok, site_scan} = SiteScans.start(run)

    assert_enqueued(worker: ScanSite, args: %{site_scan_id: site_scan.id}, queue: :site_scan)
  end

  test "a run can't have two Site Scans" do
    site_scan = insert(:site_scan)

    assert_raise Ecto.ConstraintError, fn -> SiteScans.start(site_scan.run) end
  end

  test "the scan of my run comes with its Scanned Pages in read order" do
    site_scan = insert(:site_scan)
    second = insert(:scanned_page, site_scan: site_scan, position: 2)
    first = insert(:scanned_page, site_scan: site_scan, position: 1)

    assert %SiteScan{id: site_scan_id, scanned_pages: [%ScannedPage{id: first_id}, %ScannedPage{id: second_id}]} =
             SiteScans.get_for_run(scope_for(site_scan.run.account), site_scan.run_id)

    assert {site_scan_id, first_id, second_id} == {site_scan.id, first.id, second.id}
  end

  test "the scan of another Account's run is not found through my Scope" do
    site_scan = insert(:site_scan)

    assert SiteScans.get_for_run(scope_for(insert(:account)), site_scan.run_id) == nil
  end

  test "a missing run has no scan" do
    site_scan = insert(:site_scan)

    assert SiteScans.get_for_run(scope_for(site_scan.run.account), "not-a-run") == nil
  end

  test "a run without a scan has none" do
    run = insert(:run)

    assert SiteScans.get_for_run(scope_for(run.account), run.id) == nil
  end

  test "a scan that is still scanning is found by its id with its run and its Scanned Pages" do
    page = insert(:scanned_page, site_scan: build(:site_scan, status: :scanning))

    assert %SiteScan{run: %Run{id: run_id}, scanned_pages: [%ScannedPage{id: page_id}]} =
             SiteScans.get_scanning(page.site_scan_id)

    assert {run_id, page_id} == {page.site_scan.run_id, page.id}
  end

  test "a scan that is no longer scanning is not found by its id" do
    site_scan = insert(:site_scan, status: :done)

    assert SiteScans.get_scanning(site_scan.id) == nil
  end

  test "subscribers to a run's scan are told when it changes" do
    site_scan = insert(:site_scan)
    run_id = site_scan.run_id

    :ok = SiteScans.subscribe(site_scan.run)
    :ok = SiteScans.broadcast_updated(site_scan)

    assert_received {:site_scan_updated, ^run_id}
  end

  test "subscribers to another run's scan are not told" do
    site_scan = insert(:site_scan)
    other_scan = insert(:site_scan)

    :ok = SiteScans.subscribe(other_scan.run)
    :ok = SiteScans.broadcast_updated(site_scan)

    refute_received {:site_scan_updated, _run_id}
  end

  test "a scan can't hold the same address twice" do
    page = insert(:scanned_page)

    assert_raise Ecto.ConstraintError, fn ->
      insert(:scanned_page, site_scan: page.site_scan, url: page.url)
    end
  end

  test "deleting a run deletes its scan and the scan's pages" do
    page = insert(:scanned_page)

    Repo.delete!(%Run{id: page.site_scan.run_id})

    assert Repo.get(SiteScan, page.site_scan_id) == nil
    assert Repo.get(ScannedPage, page.id) == nil
  end

  test "deleting an Account deletes its runs' scans and their pages" do
    page = insert(:scanned_page)

    Repo.delete!(%Account{id: page.site_scan.run.account_id})

    assert Repo.get(SiteScan, page.site_scan_id) == nil
    assert Repo.get(ScannedPage, page.id) == nil
  end

  test "deleting a Niche keeps the page that was matched to it, unmatched" do
    site_scan = insert(:site_scan)
    niche = insert(:niche, run: site_scan.run)
    page = insert(:scanned_page, site_scan: site_scan, niche: niche)

    Repo.delete!(%Niche{id: niche.id})

    assert %ScannedPage{cluster_id: nil} = Repo.get!(ScannedPage, page.id)
  end

  test "pages just read are stored, the pages read count follows and subscribers are told" do
    site_scan = insert(:site_scan)
    insert(:scanned_page, site_scan: site_scan, position: 1)
    run_id = site_scan.run_id
    :ok = SiteScans.subscribe(site_scan.run)

    assert %SiteScan{pages_read: 3} =
             SiteScans.record_pages(site_scan, [
               %{url: "https://#{site_scan.run.domain}/a", http_status: 200, facts: %{"title" => "A"}, position: 2},
               %{
                 url: "https://#{site_scan.run.domain}/b",
                 http_status: nil,
                 facts: %{"read_error" => "timeout"},
                 position: 3
               }
             ])

    assert %SiteScan{pages_read: 3} = Repo.reload!(site_scan)
    assert Repo.aggregate(where(ScannedPage, site_scan_id: ^site_scan.id), :count) == 3
    assert_received {:site_scan_updated, ^run_id}
  end

  test "site facts are stored next to those the scan holds" do
    site_scan = insert(:site_scan, facts: %{"home_page" => "https://a.example/", "https" => false})

    SiteScans.put_facts(site_scan, %{"https" => true, "links_checked" => 2})

    assert Repo.reload!(site_scan).facts == %{"home_page" => "https://a.example/", "https" => true, "links_checked" => 2}
  end

  test "site facts with bytes that are not UTF-8 or NUL characters are stored as text jsonb can hold" do
    site_scan = insert(:site_scan)

    SiteScans.put_facts(site_scan, %{"robots_txt" => %{"rules" => [%{"pattern" => "/k\xF3d"}]}, "name" => "A\u0000B"})

    assert Repo.reload!(site_scan).facts == %{
             "robots_txt" => %{"rules" => [%{"pattern" => "/k�d"}]},
             "name" => "AB"
           }
  end

  test "Scanned Pages whose facts hold bytes that are not UTF-8 or NUL characters are stored as text jsonb can hold" do
    site_scan = insert(:site_scan)
    url = "https://#{site_scan.run.domain}/a"

    SiteScans.record_pages(site_scan, [
      %{url: url, http_status: 200, facts: %{"title" => "Pok\xF3j", "business_name" => "A\u0000B"}, position: 1}
    ])

    assert %ScannedPage{facts: %{"title" => "Pok�j", "business_name" => "AB"}} =
             Repo.get_by!(ScannedPage, site_scan_id: site_scan.id, url: url)
  end

  test "a scan comes with at most the page limit of Scanned Pages, the first ones read" do
    site_scan = insert(:site_scan, status: :scanning)
    limit = SiteScans.page_limit()
    Enum.each((limit + 1)..1//-1, &insert(:scanned_page, site_scan: site_scan, position: &1))

    assert %SiteScan{scanned_pages: scanning_pages} = SiteScans.get_scanning(site_scan.id)

    assert %SiteScan{scanned_pages: shown_pages} =
             SiteScans.get_for_run(scope_for(site_scan.run.account), site_scan.run_id)

    assert Enum.map(scanning_pages, & &1.position) == Enum.to_list(1..limit)
    assert Enum.map(shown_pages, & &1.position) == Enum.to_list(1..limit)
  end

  test "finishing a scan marks it done and tells subscribers" do
    site_scan = insert(:site_scan, status: :scanning)
    run_id = site_scan.run_id
    :ok = SiteScans.subscribe(site_scan.run)

    SiteScans.finish(site_scan, :done)

    assert %SiteScan{status: :done, error: nil} = Repo.reload!(site_scan)
    assert_received {:site_scan_updated, ^run_id}
  end

  test "a scan that failed keeps its reason" do
    site_scan = insert(:site_scan, status: :scanning)

    SiteScans.finish(site_scan, {:failed, "The site could not be opened"})

    assert %SiteScan{status: :failed, error: "The site could not be opened"} = Repo.reload!(site_scan)
  end

  test "running my failed scan again sets it scanning without its error, enqueues its job and tells subscribers" do
    site_scan = insert(:site_scan, status: :failed, error: "The site could not be opened")
    run_id = site_scan.run_id
    :ok = SiteScans.subscribe(site_scan.run)

    assert {:ok, %SiteScan{status: :scanning, error: nil}} =
             SiteScans.retry(scope_for(site_scan.run.account), site_scan.run_id)

    assert %SiteScan{status: :scanning, error: nil} = Repo.reload!(site_scan)
    assert_enqueued(worker: ScanSite, args: %{site_scan_id: site_scan.id})
    assert_received {:site_scan_updated, ^run_id}
  end

  test "running again a scan that has not failed changes nothing and enqueues nothing" do
    site_scan = insert(:site_scan, status: :done)

    assert {:ok, %SiteScan{status: :done}} = SiteScans.retry(scope_for(site_scan.run.account), site_scan.run_id)

    refute_enqueued(worker: ScanSite)
  end

  test "the failed scan of another Account's run can't be run again through my Scope" do
    site_scan = insert(:site_scan, status: :failed, error: "The site could not be opened")

    assert {:error, :not_found} = SiteScans.retry(scope_for(insert(:account)), site_scan.run_id)

    assert %SiteScan{status: :failed} = Repo.reload!(site_scan)
    refute_enqueued(worker: ScanSite)
  end

  test "a run without a scan, or a missing run, has no scan to run again" do
    run = insert(:run)

    assert {:error, :not_found} = SiteScans.retry(scope_for(run.account), run.id)
    assert {:error, :not_found} = SiteScans.retry(scope_for(run.account), "not-a-run")
  end

  test "running again a scan that is scanning and fresh changes nothing and enqueues nothing" do
    site_scan = insert(:site_scan, status: :scanning, updated_at: minutes_ago(14))

    assert {:ok, %SiteScan{status: :scanning}} = SiteScans.retry(scope_for(site_scan.run.account), site_scan.run_id)

    assert Repo.reload!(site_scan).updated_at == site_scan.updated_at
    refute_enqueued(worker: ScanSite)
  end

  test "running again a scan stale in scanning enqueues its job past the job a restart left executing, and tells subscribers" do
    site_scan = insert(:site_scan, status: :scanning, updated_at: minutes_ago(16))
    run_id = site_scan.run_id
    lost_job = %{site_scan_id: site_scan.id} |> ScanSite.new() |> Oban.insert!()
    lost_job |> Ecto.Changeset.change(state: "executing") |> Repo.update!()
    :ok = SiteScans.subscribe(site_scan.run)

    assert {:ok, %SiteScan{status: :scanning} = restarted} =
             SiteScans.retry(scope_for(site_scan.run.account), site_scan.run_id)

    assert_enqueued(worker: ScanSite, args: %{site_scan_id: site_scan.id}, state: "available")
    assert_received {:site_scan_updated, ^run_id}
    refute SiteScans.stale?(restarted)
  end

  test "running a stale scan again twice enqueues one job" do
    site_scan = insert(:site_scan, status: :scanning, updated_at: minutes_ago(16))
    scope = scope_for(site_scan.run.account)

    {:ok, _restarted} = SiteScans.retry(scope, site_scan.run_id)
    {:ok, _unchanged} = SiteScans.retry(scope, site_scan.run_id)

    assert [_one] = all_enqueued(worker: ScanSite, args: %{site_scan_id: site_scan.id})
  end

  test "a scan is stale only while scanning with nothing stored for longer than the configured time" do
    assert SiteScans.stale?(insert(:site_scan, status: :scanning, updated_at: minutes_ago(16)))
    refute SiteScans.stale?(insert(:site_scan, status: :scanning, updated_at: minutes_ago(14)))
    refute SiteScans.stale?(insert(:site_scan, status: :done, updated_at: minutes_ago(60)))
    refute SiteScans.stale?(insert(:site_scan, status: :failed, updated_at: minutes_ago(60)))
  end

  test "storing facts the scan already holds still marks it as at work" do
    site_scan = insert(:site_scan, status: :scanning, facts: %{"https" => true}, updated_at: minutes_ago(16))

    refute site_scan |> SiteScans.put_facts(%{"https" => true}) |> SiteScans.stale?()
    refute site_scan |> Repo.reload!() |> SiteScans.stale?()
  end

  test "the report of my run's scan holds the run, the scan and the Findings worked out from its facts, Niches and Phrases" do
    site_scan =
      insert(:site_scan,
        status: :done,
        facts: %{"https" => false, "matching" => %{"done" => true, "pages" => 1, "matched" => 1}}
      )

    niche = insert(:niche, run: site_scan.run, score: Decimal.new("6"))
    home = insert(:scanned_page, site_scan: site_scan, cluster_id: niche.id, facts: %{"word_count" => 300})

    insert(:run_phrase,
      run: site_scan.run,
      niche: niche,
      current_position: Decimal.new("12"),
      current_position_url: home.url
    )

    assert {:ok, %{run: %Run{id: run_id}, scan: %SiteScan{id: site_scan_id}, findings: findings}} =
             SiteScans.report(scope_for(site_scan.run.account), site_scan.run_id)

    assert {run_id, site_scan_id} == {site_scan.run_id, site_scan.id}
    assert %Finding{level: :problem} = Enum.find(findings, &(&1.check == :https))
    assert %Finding{figures: %{niches: [%{id: niche_id}]}} = Enum.find(findings, &(&1.check == :niches_with_page))
    assert %Finding{figures: %{phrases: [%{url: url}]}} = Enum.find(findings, &(&1.check == :close_to_first_page))
    assert {niche_id, url} == {niche.id, home.url}
  end

  test "the report of a scan still at work holds its status and pages read, without its pages or Findings" do
    site_scan = insert(:site_scan, status: :scanning, pages_read: 3, facts: %{"https" => false})
    insert(:scanned_page, site_scan: site_scan)

    assert {:ok, %{scan: %SiteScan{status: :scanning, pages_read: 3, scanned_pages: pages}, findings: []}} =
             SiteScans.report(scope_for(site_scan.run.account), site_scan.run_id)

    refute Ecto.assoc_loaded?(pages)
  end

  test "the report of a run id beyond the database's id range is not found" do
    site_scan = insert(:site_scan)

    assert SiteScans.report(scope_for(site_scan.run.account), "99999999999999999999999") == {:error, :not_found}
  end

  test "the report of another Account's run is not found through my Scope" do
    site_scan = insert(:site_scan)

    assert SiteScans.report(scope_for(insert(:account)), site_scan.run_id) == {:error, :not_found}
  end

  test "the report of my run without a scan holds the run with no scan and no Findings" do
    run = insert(:run)

    assert {:ok, %{run: %Run{id: run_id}, scan: nil, findings: []}} = SiteScans.report(scope_for(run.account), run.id)
    assert run_id == run.id
  end

  test "the report judges the Phrases close to the first page among the kept ones only" do
    site_scan = insert(:site_scan, status: :done, facts: %{})
    kept = insert(:run_phrase, run: site_scan.run, current_position: Decimal.new("13"))

    insert(:run_phrase,
      run: site_scan.run,
      status: :rejected,
      current_position: Decimal.new("12"),
      current_position_url: "https://strona-testowa.example/odrzucona"
    )

    {:ok, %{findings: findings}} = SiteScans.report(scope_for(site_scan.run.account), site_scan.run_id)

    assert %Finding{figures: %{phrases: [%{phrase: phrase}]}} = Enum.find(findings, &(&1.check == :close_to_first_page))
    assert phrase == Repo.preload(kept, :phrase).phrase.phrase
  end

  test "a page the site ranks with for a rejected Phrase still counts as answering a search" do
    site_scan = insert(:site_scan, status: :done, facts: %{"matching" => %{"done" => true, "pages" => 1, "matched" => 0}})
    ranking = insert(:scanned_page, site_scan: site_scan, facts: %{"word_count" => 300})
    insert(:run_phrase, run: site_scan.run, status: :rejected, current_position_url: ranking.url)

    {:ok, %{findings: findings}} = SiteScans.report(scope_for(site_scan.run.account), site_scan.run_id)

    assert %Finding{level: :good} = Enum.find(findings, &(&1.check == :pages_answering_no_phrase))
  end

  test "the scan of my run is given without its pages, and nil for a run without one" do
    site_scan = insert(:site_scan, status: :failed)

    assert %SiteScan{id: site_scan_id, status: :failed} = SiteScans.status_of(site_scan.run)
    assert site_scan_id == site_scan.id
    assert SiteScans.status_of(insert(:run)) == nil
  end

  test "the pages matched to each Niche are given in read order once the matching is done" do
    site_scan = insert(:site_scan, facts: %{"matching" => %{"done" => true, "pages" => 3, "matched" => 2}})
    niche = insert(:niche, run: site_scan.run)
    second = insert(:scanned_page, site_scan: site_scan, cluster_id: niche.id, position: 2, facts: %{"word_count" => 9})
    first = insert(:scanned_page, site_scan: site_scan, cluster_id: niche.id, position: 1, facts: %{"word_count" => 9})
    insert(:scanned_page, site_scan: site_scan, position: 3, facts: %{"word_count" => 9})

    insert(:scanned_page,
      site_scan: site_scan,
      cluster_id: niche.id,
      position: 4,
      http_status: 404,
      facts: %{"word_count" => 9}
    )

    assert SiteScans.matched_pages_by_niche(site_scan.run) == %{niche.id => [first.url, second.url]}
  end

  test "a page matched to a Niche whose canonical names another address is not given, as the Findings leave it out" do
    site_scan = insert(:site_scan, status: :done, facts: %{"matching" => %{"done" => true, "pages" => 2, "matched" => 2}})
    niche = insert(:niche, run: site_scan.run, score: Decimal.new("6"))
    own = insert(:scanned_page, site_scan: site_scan, cluster_id: niche.id, position: 1, facts: %{"word_count" => 9})

    insert(:scanned_page,
      site_scan: site_scan,
      cluster_id: niche.id,
      position: 2,
      facts: %{"word_count" => 9, "canonical" => own.url}
    )

    assert SiteScans.matched_pages_by_niche(site_scan.run) == %{niche.id => [own.url]}

    {:ok, %{findings: findings}} = SiteScans.report(scope_for(site_scan.run.account), site_scan.run_id)
    assert %Finding{pages: [own_url]} = Enum.find(findings, &(&1.check == :niches_with_page))
    assert own_url == own.url
  end

  test "no page is matched to any Niche once a matching that matched nothing is done" do
    site_scan = insert(:site_scan, facts: %{"matching" => %{"done" => true, "pages" => 1, "matched" => 0}})
    insert(:scanned_page, site_scan: site_scan, facts: %{"word_count" => 9})

    assert SiteScans.matched_pages_by_niche(site_scan.run) == %{}
  end

  test "matched pages are not known while the matching isn't done or the run has no scan" do
    site_scan = insert(:site_scan, facts: %{"matching" => %{"done" => false, "reason" => "failed"}})
    niche = insert(:niche, run: site_scan.run)
    insert(:scanned_page, site_scan: site_scan, cluster_id: niche.id, facts: %{"word_count" => 9})

    assert SiteScans.matched_pages_by_niche(site_scan.run) == nil
    assert SiteScans.matched_pages_by_niche(insert(:site_scan).run) == nil
    assert SiteScans.matched_pages_by_niche(insert(:run)) == nil
  end

  test "an enqueue of the matching that fails is logged and still answers ok" do
    run_that_cannot_be_stored_in_a_job = %Run{id: self(), mode: :existing_site}

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert SiteScans.enqueue_matching(run_that_cannot_be_stored_in_a_job) == :ok
      end)

    assert log =~ "was not enqueued"
    refute_enqueued(worker: Dirmoon.Workers.MatchSitePages)
  end

  defp minutes_ago(minutes), do: DateTime.shift(DateTime.utc_now(:second), minute: -minutes)

  defp scope_for(account) do
    Scope.for_user(build(:user), account)
  end
end
