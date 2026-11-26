defmodule Dirmoon.Workers.ScanSiteTest do
  use Dirmoon.DataCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  import Mox

  alias Dirmoon.Research
  alias Dirmoon.Research.Run
  alias Dirmoon.SiteScans
  alias Dirmoon.SiteScans.ScannedPage
  alias Dirmoon.SiteScans.SiteScan
  alias Dirmoon.Workers.MatchSitePages
  alias Dirmoon.Workers.ScanSite

  test "a scanning scan's job reads the site and marks the scan done" do
    site_scan = insert(:site_scan, status: :scanning)
    home = "https://#{site_scan.run.domain}/"
    serve_site(home)

    assert :ok = perform_job(ScanSite, %{site_scan_id: site_scan.id})

    assert %SiteScan{status: :done, error: nil, pages_read: 1} = Repo.reload!(site_scan)
    assert [%ScannedPage{url: ^home}] = Repo.all(ScannedPage)
  end

  test "a scan that is done enqueues the matching of its pages to the run's Niches" do
    site_scan = insert(:site_scan, status: :scanning)
    serve_site("https://#{site_scan.run.domain}/")

    assert :ok = perform_job(ScanSite, %{site_scan_id: site_scan.id})

    assert_enqueued(worker: MatchSitePages, args: %{run_id: site_scan.run_id})
  end

  test "a scan that fails enqueues no matching" do
    site_scan = insert(:site_scan, status: :scanning)
    stub(Dirmoon.WebPageMock, :fetch, fn _url -> {:error, "connection refused"} end)

    assert {:cancel, _reason} = perform_job(ScanSite, %{site_scan_id: site_scan.id}, attempt: 3)

    refute_enqueued(worker: MatchSitePages)
  end

  test "subscribers are told when the scan is done" do
    site_scan = insert(:site_scan, status: :scanning)
    run_id = site_scan.run_id
    serve_site("https://#{site_scan.run.domain}/")
    :ok = SiteScans.subscribe(site_scan.run)

    :ok = perform_job(ScanSite, %{site_scan_id: site_scan.id})

    assert_received {:site_scan_updated, ^run_id}
    assert %SiteScan{status: :done} = Repo.reload!(site_scan)
  end

  test "the scan never changes the research run" do
    site_scan = insert(:site_scan, status: :scanning)
    serve_site("https://#{site_scan.run.domain}/")

    :ok = perform_job(ScanSite, %{site_scan_id: site_scan.id})

    assert %Run{status: :running} = Repo.reload!(site_scan.run)
  end

  test "without a PageSpeed key the scan is done and its facts say speed was not checked" do
    site_scan = insert(:site_scan, status: :scanning)
    serve_site("https://#{site_scan.run.domain}/")

    assert :ok = perform_job(ScanSite, %{site_scan_id: site_scan.id})

    assert %SiteScan{status: :done, facts: %{"speed" => %{"checked" => false, "reason" => "not_configured"}}} =
             Repo.reload!(site_scan)
  end

  test "the scan's indexed page count, Business Profile and linking sites are in the run's API Cost and a second run of the job buys none again" do
    site_scan = insert(:site_scan, status: :scanning)
    home = "https://#{site_scan.run.domain}/"
    business = ~s(<script type="application/ld+json">{"@type": "LocalBusiness", "name": "Azyl Gdańsk"}</script>)

    stub(Dirmoon.WebPageMock, :fetch, fn
      ^home -> {:ok, page(home, business)}
      url -> {:ok, page(url, 404, "")}
    end)

    stub(Dirmoon.PageSpeedMock, :check, fn _request -> {:error, :page_speed_quota_exceeded} end)

    expect(Dirmoon.DataForSEOMock, :indexed_page_count, 1, fn _request ->
      {:ok, %{count: 9, raw: %{"tasks" => []}, cost: Decimal.new("0.01")}}
    end)

    expect(Dirmoon.DataForSEOMock, :business_profile, 1, fn _request ->
      {:ok, %{profile: nil, raw: %{"tasks" => []}, cost: Decimal.new("0.0054")}}
    end)

    expect(Dirmoon.DataForSEOMock, :linking_sites, 1, fn %{domains: [domain]} ->
      {:ok, %{rows: [%{domain: domain, linking_sites: 6}], raw: %{"tasks" => []}, cost: Decimal.new("0.024036")}}
    end)

    :ok = perform_job(ScanSite, %{site_scan_id: site_scan.id})
    site_scan |> Repo.reload!() |> Ecto.Changeset.change(status: :scanning, facts: %{}) |> Repo.update!()

    assert :ok = perform_job(ScanSite, %{site_scan_id: site_scan.id})

    assert %SiteScan{
             status: :done,
             facts: %{
               "indexed_pages" => %{"count" => 9},
               "business_profile" => %{"found" => false},
               "linking_sites" => %{"checked" => true, "count" => 6}
             }
           } =
             Repo.reload!(site_scan)

    assert Decimal.equal?(Research.run_cost(site_scan.run), Decimal.new("0.039436"))
  end

  test "a run whose domain was stored in its Unicode form has its site read and looked up in its ASCII form" do
    run = insert(:run, mode: :existing_site, domain: "żółw.pl")
    site_scan = insert(:site_scan, run: run, status: :scanning)
    home = "https://xn--w-uga1v8h.pl/"
    serve_site(home)

    expect(Dirmoon.DataForSEOMock, :indexed_page_count, 1, fn %{domain: "xn--w-uga1v8h.pl"} ->
      {:ok, %{count: 4, raw: %{"tasks" => []}, cost: Decimal.new("0.01")}}
    end)

    expect(Dirmoon.DataForSEOMock, :linking_sites, 1, fn %{domains: ["xn--w-uga1v8h.pl"]} ->
      {:ok, %{rows: [%{domain: "xn--w-uga1v8h.pl", linking_sites: 8}], raw: %{"tasks" => []}, cost: Decimal.new("0.02")}}
    end)

    assert :ok = perform_job(ScanSite, %{site_scan_id: site_scan.id})

    assert %SiteScan{
             status: :done,
             pages_read: 1,
             facts: %{
               "home_page" => ^home,
               "indexed_pages" => %{"checked" => true, "count" => 4},
               "linking_sites" => %{"checked" => true, "count" => 8}
             }
           } = Repo.reload!(site_scan)
  end

  test "the job of a scan that is no longer scanning leaves it alone" do
    site_scan = insert(:site_scan, status: :failed, error: "The site did not answer")

    assert :ok = perform_job(ScanSite, %{site_scan_id: site_scan.id})

    assert %SiteScan{status: :failed, error: "The site did not answer"} = Repo.reload!(site_scan)
  end

  test "a second job for the same scan is not enqueued while the first is waiting" do
    site_scan = insert(:site_scan)

    {:ok, _first} = %{site_scan_id: site_scan.id} |> ScanSite.new() |> Oban.insert()
    {:ok, second} = %{site_scan_id: site_scan.id} |> ScanSite.new() |> Oban.insert()

    assert second.conflict?
  end

  test "a site that can't be opened is retried and the scan keeps scanning before the last attempt" do
    site_scan = insert(:site_scan, status: :scanning)
    stub(Dirmoon.WebPageMock, :fetch, fn _url -> {:error, "connection refused"} end)

    assert {:error, _reason} = perform_job(ScanSite, %{site_scan_id: site_scan.id}, attempt: 1)

    assert %SiteScan{status: :scanning, error: nil} = Repo.reload!(site_scan)
  end

  test "on the last attempt a site that can't be opened fails the scan with a readable reason, the run carrying on" do
    site_scan = insert(:site_scan, status: :scanning)
    run_id = site_scan.run_id
    stub(Dirmoon.WebPageMock, :fetch, fn _url -> {:error, "connection refused"} end)
    :ok = SiteScans.subscribe(site_scan.run)

    assert {:cancel, _reason} = perform_job(ScanSite, %{site_scan_id: site_scan.id}, attempt: 3)

    assert %SiteScan{status: :failed, error: "The site could not be opened: none of its addresses answered with a page"} =
             Repo.reload!(site_scan)

    assert %Run{status: :running} = Repo.reload!(site_scan.run)
    assert_received {:site_scan_updated, ^run_id}
  end

  test "an unexpected crash in the crawl is retried before the last attempt" do
    site_scan = insert(:site_scan, status: :scanning)
    stub(Dirmoon.WebPageMock, :fetch, fn _url -> raise "the reader broke" end)

    assert {:error, %RuntimeError{}} = perform_job(ScanSite, %{site_scan_id: site_scan.id}, attempt: 1)

    assert %SiteScan{status: :scanning} = Repo.reload!(site_scan)
  end

  test "an unexpected crash in the crawl fails the scan on the last attempt with a readable reason" do
    site_scan = insert(:site_scan, status: :scanning)
    stub(Dirmoon.WebPageMock, :fetch, fn _url -> raise "the reader broke" end)

    assert {:cancel, _reason} = perform_job(ScanSite, %{site_scan_id: site_scan.id}, attempt: 3)

    assert %SiteScan{status: :failed, error: "Unexpected error: the reader broke"} = Repo.reload!(site_scan)
    assert %Run{status: :running} = Repo.reload!(site_scan.run)
  end

  test "an exit in the crawl fails the scan on the last attempt with a readable reason" do
    site_scan = insert(:site_scan, status: :scanning)
    stub(Dirmoon.WebPageMock, :fetch, fn _url -> exit(:reader_gone) end)

    assert {:cancel, {:exit, :reader_gone}} = perform_job(ScanSite, %{site_scan_id: site_scan.id}, attempt: 3)

    assert %SiteScan{status: :failed, error: "Unexpected error: {:exit, :reader_gone}"} = Repo.reload!(site_scan)
  end

  test "a throw in the crawl is retried before the last attempt and fails the scan on it" do
    site_scan = insert(:site_scan, status: :scanning)
    stub(Dirmoon.WebPageMock, :fetch, fn _url -> throw(:reader_gave_up) end)

    assert {:error, {:throw, :reader_gave_up}} = perform_job(ScanSite, %{site_scan_id: site_scan.id}, attempt: 1)
    assert %SiteScan{status: :scanning} = Repo.reload!(site_scan)

    assert {:cancel, {:throw, :reader_gave_up}} = perform_job(ScanSite, %{site_scan_id: site_scan.id}, attempt: 3)
    assert %SiteScan{status: :failed, error: "Unexpected error: {:throw, :reader_gave_up}"} = Repo.reload!(site_scan)
  end

  test "a job run again after pages were stored does not read them again" do
    site_scan = insert(:site_scan, status: :scanning)
    home = "https://#{site_scan.run.domain}/"
    oferta = home <> "oferta"
    test_pid = self()
    stored_site_scan = site_scan |> Ecto.Changeset.change(pages_read: 1, facts: site_facts(home)) |> Repo.update!()

    insert(:scanned_page,
      site_scan: stored_site_scan,
      url: home,
      position: 1,
      facts: %{"final_url" => home, "internal_links" => [oferta]}
    )

    google_not_configured()

    stub(Dirmoon.WebPageMock, :fetch, fn url ->
      send(test_pid, {:fetched, url})
      {:ok, page(url, "<p>Strona</p>")}
    end)

    :ok = perform_job(ScanSite, %{site_scan_id: site_scan.id}, attempt: 2)

    refute_received {:fetched, ^home}
    assert_received {:fetched, ^oferta}
    assert %SiteScan{status: :done, pages_read: 2} = Repo.reload!(site_scan)
  end

  test "a speed check that raises, exits or throws on the last attempt is not checked and the scan is done" do
    for crash <- crashes() do
      site_scan = insert(:site_scan, status: :scanning)
      serve_site("https://#{site_scan.run.domain}/")
      stub(Dirmoon.PageSpeedMock, :check, fn _request -> crash.() end)

      assert :ok = perform_job(ScanSite, %{site_scan_id: site_scan.id}, attempt: 3)

      assert %SiteScan{status: :done, facts: %{"speed" => %{"checked" => false, "reason" => "failed"}}} =
               Repo.reload!(site_scan)
    end
  end

  test "an indexed page count that raises, exits or throws on the last attempt is not checked and the scan is done" do
    for crash <- crashes() do
      site_scan = insert(:site_scan, status: :scanning)
      serve_site("https://#{site_scan.run.domain}/")
      stub(Dirmoon.DataForSEOMock, :indexed_page_count, fn _request -> crash.() end)

      assert :ok = perform_job(ScanSite, %{site_scan_id: site_scan.id}, attempt: 3)

      assert %SiteScan{status: :done, facts: %{"indexed_pages" => %{"checked" => false, "reason" => "failed"}}} =
               Repo.reload!(site_scan)
    end
  end

  test "a Business Profile lookup that raises, exits or throws on the last attempt is not checked and the scan is done" do
    for crash <- crashes() do
      site_scan = insert(:site_scan, status: :scanning)
      home = "https://#{site_scan.run.domain}/"
      business = ~s(<script type="application/ld+json">{"@type": "LocalBusiness", "name": "Azyl Gdańsk"}</script>)
      serve_site(home, business)
      stub(Dirmoon.DataForSEOMock, :business_profile, fn _request -> crash.() end)

      assert :ok = perform_job(ScanSite, %{site_scan_id: site_scan.id}, attempt: 3)

      assert %SiteScan{status: :done, facts: %{"business_profile" => %{"checked" => false, "reason" => "failed"}}} =
               Repo.reload!(site_scan)
    end
  end

  test "a linking sites lookup that raises, exits or throws on the last attempt is not checked and the scan is done" do
    for crash <- crashes() do
      site_scan = insert(:site_scan, status: :scanning)
      serve_site("https://#{site_scan.run.domain}/")
      stub(Dirmoon.DataForSEOMock, :linking_sites, fn _request -> crash.() end)

      assert :ok = perform_job(ScanSite, %{site_scan_id: site_scan.id}, attempt: 3)

      assert %SiteScan{status: :done, facts: %{"linking_sites" => %{"checked" => false, "reason" => "failed"}}} =
               Repo.reload!(site_scan)
    end
  end

  defp crashes do
    [fn -> raise "the check broke" end, fn -> exit(:check_gone) end, fn -> throw(:check_gave_up) end]
  end

  defp serve_site(home, html \\ "<h1>Start</h1>") do
    google_not_configured()

    stub(Dirmoon.WebPageMock, :fetch, fn
      ^home -> {:ok, page(home, html)}
      url -> {:ok, page(url, 404, "")}
    end)
  end

  defp page(url, status \\ 200, html),
    do: %{url: url, status: status, redirects: [], content_type: "text/html", body: html}

  defp site_facts(home) do
    %{
      "home_page" => home,
      "robots_txt" => %{"sitemaps" => []},
      "sitemap" => %{"pages" => []}
    }
  end

  defp google_not_configured do
    stub(Dirmoon.PageSpeedMock, :check, fn _request -> {:error, :page_speed_not_configured} end)
    stub(Dirmoon.DataForSEOMock, :indexed_page_count, fn _request -> {:error, :data_for_seo_not_configured} end)
    stub(Dirmoon.DataForSEOMock, :business_profile, fn _request -> {:error, :data_for_seo_not_configured} end)
    stub(Dirmoon.DataForSEOMock, :linking_sites, fn _request -> {:error, :data_for_seo_not_configured} end)
  end
end
