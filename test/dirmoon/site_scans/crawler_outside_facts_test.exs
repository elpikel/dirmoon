defmodule Dirmoon.SiteScans.CrawlerOutsideFactsTest do
  use Dirmoon.DataCase, async: true

  import Mox

  alias Dirmoon.PageSpeed.HTTP
  alias Dirmoon.Research
  alias Dirmoon.Research.ApiRequest
  alias Dirmoon.Research.Ledger
  alias Dirmoon.SiteScans
  alias Dirmoon.SiteScans.Crawler
  alias Dirmoon.SiteScans.SiteScan

  @speed_result %{
    "performance_score" => 58,
    "largest_contentful_paint_ms" => 4210,
    "total_blocking_time_ms" => 380,
    "cumulative_layout_shift" => 0.21,
    "lighthouse_version" => "13.0.1",
    "field" => %{},
    "phone_checks" => [%{"id" => "target-size", "passed" => false}]
  }

  test "the home page's phone speed is stored with its figures and phone checks" do
    site_scan = insert(:site_scan)
    home = serve_home(site_scan)
    data_for_seo_not_configured()

    expect(Dirmoon.PageSpeedMock, :check, 1, fn %{url: ^home} ->
      {:ok, %{result: @speed_result, raw: %{"kind" => "pagespeedonline#result", "id" => home}}}
    end)

    assert {:ok, %SiteScan{facts: %{"speed" => speed}}} = crawl(site_scan)

    assert speed == Map.put(@speed_result, "checked", true)
  end

  test "the speed check is in the run's ledger at no cost, holding only the page address and the phone strategy" do
    site_scan = insert(:site_scan)
    home = serve_home(site_scan)
    data_for_seo_not_configured()
    stub(Dirmoon.PageSpeedMock, :check, fn _request -> {:ok, %{result: @speed_result, raw: %{"id" => home}}} end)

    {:ok, _site_scan} = crawl(site_scan)

    assert [%ApiRequest{request: request, response: response, cost: cost}] = ledger_entries(site_scan, "page_speed")
    assert request == %{"url" => home, "strategy" => "mobile"}
    assert response == %{"result" => @speed_result, "raw" => %{"id" => home}}
    assert Decimal.equal?(cost, 0)
  end

  test "without a PageSpeed key the scan finishes and the speed is not checked" do
    site_scan = insert(:site_scan)
    serve_home(site_scan)
    google_not_configured()

    assert {:ok, %SiteScan{facts: %{"speed" => speed}}} = crawl(site_scan)

    assert speed == %{"checked" => false, "reason" => "not_configured"}
    assert ledger_entries(site_scan, "page_speed") == []
  end

  test "a speed check PageSpeed refuses or can't do is not checked, with the reason" do
    for {error, reason} <- [
          {:page_speed_key_rejected, "not_configured"},
          {:page_speed_quota_exceeded, "quota"},
          {:page_unreachable, "page_unreachable"},
          {{:page_speed_failed, "PageSpeed: timeout"}, "failed"}
        ] do
      site_scan = insert(:site_scan)
      serve_home(site_scan)
      data_for_seo_not_configured()
      expect(Dirmoon.PageSpeedMock, :check, 1, fn _request -> {:error, error} end)

      assert {:ok, %SiteScan{facts: %{"speed" => speed}}} = crawl(site_scan)

      assert speed == %{"checked" => false, "reason" => reason}
    end
  end

  test "a resumed scan keeps a stored speed fact, unless the check failed" do
    for stored <- [Map.put(@speed_result, "checked", true), %{"checked" => false, "reason" => "quota"}] do
      site_scan = scan_with_stored_facts(%{"speed" => stored})
      data_for_seo_not_configured()
      expect(Dirmoon.PageSpeedMock, :check, 0, fn _request -> {:error, :page_speed_quota_exceeded} end)

      assert {:ok, %SiteScan{facts: %{"speed" => ^stored}}} = crawl(site_scan)
    end

    site_scan = scan_with_stored_facts(%{"speed" => %{"checked" => false, "reason" => "failed"}})
    data_for_seo_not_configured()
    expect(Dirmoon.PageSpeedMock, :check, 1, fn _request -> {:ok, %{result: @speed_result, raw: %{}}} end)

    assert {:ok, %SiteScan{facts: %{"speed" => %{"checked" => true, "performance_score" => 58}}}} = crawl(site_scan)
  end

  test "a speed check the run's ledger already holds is replayed, not asked again" do
    site_scan = insert(:site_scan)
    home = serve_home(site_scan)
    data_for_seo_not_configured()

    {:ok, _response} =
      Ledger.fetch(
        site_scan.run,
        %{service: "page_speed", operation: "check", request: %{url: home, strategy: "mobile"}},
        fn -> {:ok, %{"result" => @speed_result, "raw" => %{}}, 0} end
      )

    expect(Dirmoon.PageSpeedMock, :check, 0, fn _request -> {:error, :page_speed_not_configured} end)

    assert {:ok, %SiteScan{facts: %{"speed" => %{"checked" => true, "performance_score" => 58}}}} = crawl(site_scan)
  end

  test "Google's indexed page count for the run's domain, in its country, is stored and paid for once" do
    site_scan = city_scan()
    run = site_scan.run
    serve_home(site_scan)
    page_speed_not_configured()
    stub(Dirmoon.DataForSEOMock, :business_profile, fn _request -> {:error, :data_for_seo_not_configured} end)

    expect(Dirmoon.DataForSEOMock, :indexed_page_count, 1, fn request ->
      assert request == %{domain: run.domain, location_code: run.location_code, language_code: run.language_code}
      {:ok, %{count: 37, raw: %{"tasks" => []}, cost: Decimal.new("0.01")}}
    end)

    assert {:ok, %SiteScan{facts: %{"indexed_pages" => indexed_pages}}} = crawl(site_scan)

    assert indexed_pages == %{"checked" => true, "count" => 37}
    assert Decimal.equal?(Research.run_cost(run), Decimal.new("0.01"))
  end

  test "an indexed page count DataForSEO can't give is not checked, with the reason, and the scan finishes" do
    for {error, reason} <- [
          {:data_for_seo_not_configured, "not_configured"},
          {:not_in_demo_data, "not_in_demo_data"},
          {"DataForSEO: HTTP 500", "failed"}
        ] do
      site_scan = insert(:site_scan)
      serve_home(site_scan)
      page_speed_not_configured()
      stub(Dirmoon.DataForSEOMock, :business_profile, fn _request -> {:error, :data_for_seo_not_configured} end)
      expect(Dirmoon.DataForSEOMock, :indexed_page_count, 1, fn _request -> {:error, error} end)

      assert {:ok, %SiteScan{facts: %{"indexed_pages" => indexed_pages}}} = crawl(site_scan)

      assert indexed_pages == %{"checked" => false, "reason" => reason}
    end
  end

  test "a resumed scan keeps a stored indexed page count and asks again for one not checked" do
    site_scan = scan_with_stored_facts(%{"indexed_pages" => %{"checked" => true, "count" => 12}})
    page_speed_not_configured()
    stub(Dirmoon.DataForSEOMock, :business_profile, fn _request -> {:error, :data_for_seo_not_configured} end)
    expect(Dirmoon.DataForSEOMock, :indexed_page_count, 0, fn _request -> {:error, :data_for_seo_not_configured} end)

    assert {:ok, %SiteScan{facts: %{"indexed_pages" => %{"checked" => true, "count" => 12}}}} = crawl(site_scan)

    site_scan = scan_with_stored_facts(%{"indexed_pages" => %{"checked" => false, "reason" => "failed"}})
    expect(Dirmoon.DataForSEOMock, :indexed_page_count, 1, fn _request -> {:ok, %{count: 3, raw: %{}, cost: 0}} end)

    assert {:ok, %SiteScan{facts: %{"indexed_pages" => %{"checked" => true, "count" => 3}}}} = crawl(site_scan)
  end

  test "the business named in the home page's structured data is looked up in the run's city and its profile stored" do
    site_scan = city_scan()
    run = site_scan.run
    serve_home(site_scan, business_markup("Hotel dla psów Azyl"))
    page_speed_not_configured()
    stub(Dirmoon.DataForSEOMock, :indexed_page_count, fn _request -> {:error, :data_for_seo_not_configured} end)

    expect(Dirmoon.DataForSEOMock, :business_profile, 1, fn request ->
      assert request == %{
               name: "Hotel dla psów Azyl",
               location_code: run.city_location_code,
               language_code: run.language_code
             }

      {:ok,
       %{
         profile: profile(%{domain: "www." <> run.domain, url: "https://www." <> run.domain <> "/"}),
         raw: %{"tasks" => []},
         cost: Decimal.new("0.0054")
       }}
    end)

    assert {:ok, %SiteScan{facts: %{"business_profile" => business_profile}}} = crawl(site_scan)

    assert business_profile == %{
             "checked" => true,
             "name" => "Hotel dla psów Azyl",
             "found" => true,
             "links_to_site" => true,
             "title" => "Hotel dla psów Azyl",
             "phone" => "+48 500 000 001",
             "address" => "ul. Spacerowa 2, Gdańsk",
             "rating" => 4.8,
             "votes" => 21,
             "claimed" => false
           }

    assert Decimal.equal?(Research.run_cost(run), Decimal.new("0.0054"))
  end

  test "a run without a city looks the business up in its country" do
    site_scan = insert(:site_scan)
    run = site_scan.run
    serve_home(site_scan, business_markup("Hotel dla psów Azyl"))
    page_speed_not_configured()
    stub(Dirmoon.DataForSEOMock, :indexed_page_count, fn _request -> {:error, :data_for_seo_not_configured} end)

    expect(Dirmoon.DataForSEOMock, :business_profile, 1, fn %{location_code: location_code} ->
      assert location_code == run.location_code
      {:ok, %{profile: nil, raw: %{}, cost: Decimal.new("0.0054")}}
    end)

    assert {:ok, %SiteScan{facts: %{"business_profile" => %{"checked" => true}}}} = crawl(site_scan)
  end

  test "a profile whose website is elsewhere, or that has none, does not link to the site" do
    for {profile_site, links_to_site} <- [
          {%{domain: "inna-strona.example", url: "https://inna-strona.example/"}, false},
          {%{domain: nil, url: nil}, false},
          {%{domain: "", url: "https://WWW.%{domain}/kontakt"}, true},
          {%{domain: nil, url: "nie adres"}, false}
        ] do
      site_scan = insert(:site_scan)
      domain = site_scan.run.domain
      serve_home(site_scan, business_markup("Hotel dla psów Azyl"))
      page_speed_not_configured()
      stub(Dirmoon.DataForSEOMock, :indexed_page_count, fn _request -> {:error, :data_for_seo_not_configured} end)
      url = profile_site.url && String.replace(profile_site.url, "%{domain}", domain)

      expect(Dirmoon.DataForSEOMock, :business_profile, 1, fn _request ->
        {:ok, %{profile: profile(%{profile_site | url: url}), raw: %{}, cost: Decimal.new("0.0054")}}
      end)

      assert {:ok, %SiteScan{facts: %{"business_profile" => %{"found" => true, "links_to_site" => ^links_to_site}}}} =
               crawl(site_scan)
    end
  end

  test "a profile giving an international site's domain in its Unicode form links to the site" do
    site_scan = insert(:site_scan, run: build(:run, mode: :existing_site, domain: "xn--w-uga1v8h.pl"))
    serve_home(site_scan, business_markup("Hotel dla psów Azyl"))
    page_speed_not_configured()
    stub(Dirmoon.DataForSEOMock, :indexed_page_count, fn _request -> {:error, :data_for_seo_not_configured} end)

    expect(Dirmoon.DataForSEOMock, :business_profile, 1, fn _request ->
      {:ok, %{profile: profile(%{domain: "www.Żółw.pl", url: nil}), raw: %{}, cost: Decimal.new("0.0054")}}
    end)

    assert {:ok, %SiteScan{facts: %{"business_profile" => %{"found" => true, "links_to_site" => true}}}} =
             crawl(site_scan)
  end

  test "a business Google has no profile for is stored as looked up and not found" do
    site_scan = insert(:site_scan)
    serve_home(site_scan, business_markup("Hotel dla psów Azyl"))
    page_speed_not_configured()
    stub(Dirmoon.DataForSEOMock, :indexed_page_count, fn _request -> {:error, :data_for_seo_not_configured} end)
    expect(Dirmoon.DataForSEOMock, :business_profile, 1, fn _request -> {:ok, %{profile: nil, raw: %{}, cost: 0}} end)

    assert {:ok, %SiteScan{facts: %{"business_profile" => business_profile}}} = crawl(site_scan)

    assert business_profile == %{
             "checked" => true,
             "name" => "Hotel dla psów Azyl",
             "found" => false,
             "links_to_site" => false,
             "title" => nil,
             "phone" => nil,
             "address" => nil,
             "rating" => nil,
             "votes" => nil,
             "claimed" => nil
           }
  end

  test "without a business name in the structured data the profile is not looked up, whatever the page title" do
    site_scan = insert(:site_scan)
    serve_home(site_scan, "<title>Hotel dla psów Azyl</title><h1>Witamy</h1>")
    page_speed_not_configured()
    stub(Dirmoon.DataForSEOMock, :indexed_page_count, fn _request -> {:error, :data_for_seo_not_configured} end)
    expect(Dirmoon.DataForSEOMock, :business_profile, 0, fn _request -> {:error, :data_for_seo_not_configured} end)

    assert {:ok, %SiteScan{facts: %{"business_profile" => business_profile}}} = crawl(site_scan)

    assert business_profile == %{"checked" => false, "reason" => "no_business_name"}
  end

  test "the home page's business name comes first, and another page's is used when the home page has none" do
    for {home_name, expected} <- [{"Azyl Gdańsk", "Azyl Gdańsk"}, {nil, "Azyl z podstrony"}] do
      site_scan = insert(:site_scan)
      home = "https://#{site_scan.run.domain}/"
      home_markup = if home_name, do: business_markup(home_name), else: "<p>Start</p>"

      serve(%{
        home => html_page(home, home_markup <> ~s(<a href="/kontakt">Kontakt</a>)),
        (home <> "kontakt") => html_page(home <> "kontakt", business_markup("Azyl z podstrony"))
      })

      page_speed_not_configured()
      stub(Dirmoon.DataForSEOMock, :indexed_page_count, fn _request -> {:error, :data_for_seo_not_configured} end)

      expect(Dirmoon.DataForSEOMock, :business_profile, 1, fn %{name: name} ->
        assert name == expected
        {:ok, %{profile: nil, raw: %{}, cost: 0}}
      end)

      assert {:ok, %SiteScan{facts: %{"business_profile" => %{"name" => ^expected}}}} = crawl(site_scan)
    end
  end

  test "a lookup DataForSEO refuses for the location is not checked as unavailable, and its cost is recorded once" do
    site_scan = insert(:site_scan)
    run = site_scan.run
    serve_home(site_scan, business_markup("Hotel dla psów Azyl"))
    page_speed_not_configured()
    stub(Dirmoon.DataForSEOMock, :indexed_page_count, fn _request -> {:error, :data_for_seo_not_configured} end)

    expect(Dirmoon.DataForSEOMock, :business_profile, 1, fn _request ->
      {:error,
       {:business_profile_unavailable,
        %{message: "DataForSEO: Invalid Field: 'location_code'.", raw: %{}, cost: Decimal.new("0.0054")}}}
    end)

    assert {:ok, %SiteScan{facts: %{"business_profile" => business_profile}}} = crawl(site_scan)
    assert business_profile == %{"checked" => false, "reason" => "unavailable"}

    site_scan |> Repo.reload!() |> Ecto.Changeset.change(facts: %{}) |> Repo.update!()

    assert {:ok, %SiteScan{facts: %{"business_profile" => %{"reason" => "unavailable"}}}} = crawl(site_scan)
    assert Decimal.equal?(Research.run_cost(run), Decimal.new("0.0054"))
  end

  test "a lookup DataForSEO can't make is not checked, with the reason, and the scan finishes" do
    for {error, reason} <- [
          {:data_for_seo_not_configured, "not_configured"},
          {:not_in_demo_data, "not_in_demo_data"},
          {"DataForSEO: Insufficient Funds.", "failed"}
        ] do
      site_scan = insert(:site_scan)
      serve_home(site_scan, business_markup("Hotel dla psów Azyl"))
      page_speed_not_configured()
      stub(Dirmoon.DataForSEOMock, :indexed_page_count, fn _request -> {:error, :data_for_seo_not_configured} end)
      expect(Dirmoon.DataForSEOMock, :business_profile, 1, fn _request -> {:error, error} end)

      assert {:ok, %SiteScan{facts: %{"business_profile" => business_profile}}} = crawl(site_scan)

      assert business_profile == %{"checked" => false, "reason" => reason}
    end
  end

  test "the profile's name, phone and address are cleaned and cut to 300 bytes, and a missing one stays empty" do
    site_scan = insert(:site_scan)
    serve_home(site_scan, business_markup("Hotel dla psów Azyl"))
    page_speed_not_configured()
    stub(Dirmoon.DataForSEOMock, :indexed_page_count, fn _request -> {:error, :data_for_seo_not_configured} end)
    long_address = String.duplicate("ą", 400)

    expect(Dirmoon.DataForSEOMock, :business_profile, 1, fn _request ->
      profile = %{profile(%{domain: nil, url: nil}) | address: long_address, title: "Azyl\0 Gdańsk", phone: nil}
      {:ok, %{profile: profile, raw: %{}, cost: 0}}
    end)

    assert {:ok, %SiteScan{facts: %{"business_profile" => business_profile}}} = crawl(site_scan)

    assert business_profile["title"] == "Azyl Gdańsk"
    assert business_profile["address"] == String.duplicate("ą", 150)
    assert business_profile["phone"] == nil
  end

  test "a resumed scan keeps a stored Business Profile and doesn't look it up again" do
    stored = %{"checked" => true, "name" => "Azyl", "found" => false, "links_to_site" => false}
    site_scan = scan_with_stored_facts(%{"business_profile" => stored})
    page_speed_not_configured()
    stub(Dirmoon.DataForSEOMock, :indexed_page_count, fn _request -> {:error, :data_for_seo_not_configured} end)
    expect(Dirmoon.DataForSEOMock, :business_profile, 0, fn _request -> {:error, :data_for_seo_not_configured} end)

    assert {:ok, %SiteScan{facts: %{"business_profile" => ^stored}}} = crawl(site_scan)
  end

  test "how many other sites link to the run's domain is stored and paid for once" do
    site_scan = insert(:site_scan)
    run = site_scan.run
    serve_home(site_scan)
    page_speed_not_configured()
    stub(Dirmoon.DataForSEOMock, :indexed_page_count, fn _request -> {:error, :data_for_seo_not_configured} end)
    stub(Dirmoon.DataForSEOMock, :business_profile, fn _request -> {:error, :data_for_seo_not_configured} end)

    expect(Dirmoon.DataForSEOMock, :linking_sites, 1, fn request ->
      assert request == %{domains: [run.domain]}
      {:ok, %{rows: [%{domain: run.domain, linking_sites: 17}], raw: %{"tasks" => []}, cost: Decimal.new("0.024036")}}
    end)

    assert {:ok, %SiteScan{facts: %{"linking_sites" => linking_sites}}} = crawl(site_scan)
    assert linking_sites == %{"checked" => true, "count" => 17}

    site_scan |> Repo.reload!() |> Ecto.Changeset.change(facts: %{}) |> Repo.update!()

    assert {:ok, %SiteScan{facts: %{"linking_sites" => %{"count" => 17}}}} = crawl(site_scan)
    assert Decimal.equal?(Research.run_cost(run), Decimal.new("0.024036"))
    assert [%ApiRequest{request: %{"domains" => [_domain]}}] = ledger_entries(site_scan, "dataforseo")
  end

  test "a domain DataForSEO's link index has no data for is checked with no count, never zero" do
    site_scan = insert(:site_scan)
    serve_home(site_scan)
    data_for_seo_not_configured()
    page_speed_not_configured()

    expect(Dirmoon.DataForSEOMock, :linking_sites, 1, fn _request ->
      {:ok, %{rows: [], raw: %{"tasks" => []}, cost: Decimal.new("0.024")}}
    end)

    assert {:ok, %SiteScan{facts: %{"linking_sites" => linking_sites}}} = crawl(site_scan)
    assert linking_sites == %{"checked" => true, "count" => nil}
  end

  test "linking sites DataForSEO refuses are not checked as unavailable, and the refusal's cost is recorded once" do
    site_scan = insert(:site_scan)
    run = site_scan.run
    serve_home(site_scan)
    data_for_seo_not_configured()
    page_speed_not_configured()

    expect(Dirmoon.DataForSEOMock, :linking_sites, 1, fn _request ->
      {:error,
       {:linking_sites_unavailable, %{message: "DataForSEO: Access denied.", raw: %{}, cost: Decimal.new("0.024")}}}
    end)

    assert {:ok, %SiteScan{facts: %{"linking_sites" => linking_sites}}} = crawl(site_scan)
    assert linking_sites == %{"checked" => false, "reason" => "unavailable"}

    site_scan |> Repo.reload!() |> Ecto.Changeset.change(facts: %{}) |> Repo.update!()

    assert {:ok, %SiteScan{facts: %{"linking_sites" => %{"reason" => "unavailable"}}}} = crawl(site_scan)
    assert Decimal.equal?(Research.run_cost(run), Decimal.new("0.024"))
  end

  test "linking sites DataForSEO can't give are not checked, with the reason, and the scan finishes" do
    for {error, reason} <- [
          {:data_for_seo_not_configured, "not_configured"},
          {:not_in_demo_data, "not_in_demo_data"},
          {"DataForSEO: Insufficient Funds.", "failed"}
        ] do
      site_scan = insert(:site_scan)
      serve_home(site_scan)
      data_for_seo_not_configured()
      page_speed_not_configured()
      expect(Dirmoon.DataForSEOMock, :linking_sites, 1, fn _request -> {:error, error} end)

      assert {:ok, %SiteScan{facts: %{"linking_sites" => linking_sites}}} = crawl(site_scan)
      assert linking_sites == %{"checked" => false, "reason" => reason}
    end
  end

  test "a resumed scan keeps stored linking sites and asks again for ones not checked" do
    stored = %{"checked" => true, "count" => nil}
    site_scan = scan_with_stored_facts(%{"linking_sites" => stored})
    page_speed_not_configured()
    stub(Dirmoon.DataForSEOMock, :indexed_page_count, fn _request -> {:error, :data_for_seo_not_configured} end)
    stub(Dirmoon.DataForSEOMock, :business_profile, fn _request -> {:error, :data_for_seo_not_configured} end)
    expect(Dirmoon.DataForSEOMock, :linking_sites, 0, fn _request -> {:error, :data_for_seo_not_configured} end)

    assert {:ok, %SiteScan{facts: %{"linking_sites" => ^stored}}} = crawl(site_scan)

    site_scan = scan_with_stored_facts(%{"linking_sites" => %{"checked" => false, "reason" => "failed"}})

    expect(Dirmoon.DataForSEOMock, :linking_sites, 1, fn %{domains: [domain]} ->
      {:ok, %{rows: [%{domain: domain, linking_sites: 0}], raw: %{}, cost: 0}}
    end)

    assert {:ok, %SiteScan{facts: %{"linking_sites" => %{"checked" => true, "count" => 0}}}} = crawl(site_scan)
  end

  test "the speed check's ledger row holds no screenshot from Google's answer" do
    site_scan = insert(:site_scan)
    serve_home(site_scan)
    data_for_seo_not_configured()
    screenshot = "data:image/jpeg;base64," <> String.duplicate("QUJD", 1_000)
    stub(Dirmoon.PageSpeedMock, :check, &HTTP.check/1)

    Req.Test.stub(HTTP, fn conn ->
      Req.Test.json(conn, %{
        "lighthouseResult" => %{
          "lighthouseVersion" => "13.0.1",
          "fullPageScreenshot" => %{"screenshot" => %{"data" => screenshot}},
          "audits" => %{
            "final-screenshot" => %{"id" => "final-screenshot", "details" => %{"data" => screenshot}}
          }
        }
      })
    end)

    {:ok, %SiteScan{facts: %{"speed" => %{"checked" => true}}}} = crawl(site_scan)

    assert [%ApiRequest{response: response}] = ledger_entries(site_scan, "page_speed")
    refute response |> Jason.encode!() |> String.contains?("base64")
  end

  defp crawl(site_scan) do
    site_scan.id
    |> SiteScans.get_scanning()
    |> Crawler.crawl()
  end

  defp ledger_entries(site_scan, service) do
    ApiRequest
    |> from(as: :api_request)
    |> where([api_request: api_request], api_request.run_id == ^site_scan.run_id and api_request.service == ^service)
    |> Repo.all()
  end

  defp city_scan do
    site_scan = insert(:site_scan)
    run = site_scan.run |> Ecto.Changeset.change(city: "Gdańsk", city_location_code: 1_011_700) |> Repo.update!()
    %{site_scan | run: run}
  end

  defp scan_with_stored_facts(outside_facts) do
    site_scan = insert(:site_scan)
    home = serve_home(site_scan, business_markup("Hotel dla psów Azyl"))

    site_scan
    |> Ecto.Changeset.change(facts: Map.merge(stored_site_facts(home), outside_facts))
    |> Repo.update!()
  end

  defp serve_home(site_scan, html \\ "<h1>Start</h1>") do
    home = "https://#{site_scan.run.domain}/"
    serve(%{home => html_page(home, html)})
    home
  end

  defp serve(answers) do
    stub(Dirmoon.WebPageMock, :fetch, fn url ->
      Map.get_lazy(answers, url, fn -> html_page(url, 404, "") end)
    end)
  end

  defp html_page(url, status \\ 200, html),
    do: {:ok, %{url: url, status: status, redirects: [], content_type: "text/html", body: html}}

  defp business_markup(name) do
    ~s(<script type="application/ld+json">{"@type": "LocalBusiness", "name": "#{name}"}</script>)
  end

  defp profile(%{domain: domain, url: url}) do
    %{
      title: "Hotel dla psów Azyl",
      address: "ul. Spacerowa 2, Gdańsk",
      phone: "+48 500 000 001",
      url: url,
      domain: domain,
      rating: 4.8,
      votes: 21,
      claimed: false
    }
  end

  defp stored_site_facts(home) do
    %{
      "home_page" => home,
      "addresses" => [],
      "https" => true,
      "www_and_bare_both_answer" => false,
      "robots_txt" => %{
        "present" => false,
        "status" => 404,
        "unreadable" => false,
        "blocks_site" => false,
        "sitemaps" => []
      },
      "sitemap" => %{"found" => false, "url" => nil, "page_count" => 0, "pages" => []}
    }
  end

  defp google_not_configured do
    page_speed_not_configured()
    data_for_seo_not_configured()
  end

  defp page_speed_not_configured do
    stub(Dirmoon.PageSpeedMock, :check, fn _request -> {:error, :page_speed_not_configured} end)
  end

  defp data_for_seo_not_configured do
    stub(Dirmoon.DataForSEOMock, :indexed_page_count, fn _request -> {:error, :data_for_seo_not_configured} end)
    stub(Dirmoon.DataForSEOMock, :business_profile, fn _request -> {:error, :data_for_seo_not_configured} end)
    stub(Dirmoon.DataForSEOMock, :linking_sites, fn _request -> {:error, :data_for_seo_not_configured} end)
  end
end
