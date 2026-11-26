defmodule Dirmoon.SiteScans.CrawlerRobotsTest do
  # Not async: it counts calls to Robots.allowed?/2 across every process,
  # so no other test may crawl meanwhile.
  use Dirmoon.DataCase, async: false

  import Mox

  alias Dirmoon.SiteScans
  alias Dirmoon.SiteScans.Crawler
  alias Dirmoon.SiteScans.Robots
  alias Dirmoon.SiteScans.SiteScan

  test "a hostile robots.txt is cut down and each address is checked against it once, however often it is linked" do
    site_scan = insert(:site_scan)
    home = "https://#{site_scan.run.domain}/"
    hostile_rule = "Disallow: /" <> String.duplicate("*a", 900) <> "\n"
    plain_rules = Enum.map_join(1..600, &"Disallow: /zablokowana-#{&1}\n")
    robots_txt = "User-agent: *\n" <> String.duplicate(hostile_rule, 1_000) <> plain_rules
    linked = Enum.map(1..15, &"/strona-#{&1}") ++ Enum.map(1..5, &"/zablokowana-#{&1}")
    every_page_links = Enum.map_join(["/" | linked], &~s(<a href="#{&1}">L</a>))

    stub(Dirmoon.WebPageMock, :fetch, fn url ->
      cond do
        url == home <> "robots.txt" -> page(url, %{status: 200, content_type: "text/plain", body: robots_txt})
        url == home <> "sitemap.xml" -> page(url, %{status: 404, content_type: "text/html", body: ""})
        String.starts_with?(url, home) -> page(url, %{status: 200, content_type: "text/html", body: every_page_links})
        true -> {:error, "connection refused"}
      end
    end)

    %{crawled: {:ok, %SiteScan{facts: facts}}, robots_checks: robots_checks} =
      count_robots_checks(fn -> crawl(site_scan) end)

    refute Map.has_key?(facts["robots_txt"], "rules")
    assert Enum.count(facts["blocked_pages"]) == 5
    assert robots_checks == 1 + Enum.count(["/" | linked])
  end

  test "a site whose every page links a hundred new addresses, half of them disallowed, costs at most a few hundred robots checks" do
    site_scan = insert(:site_scan)
    home = "https://#{site_scan.run.domain}/"
    limit = SiteScans.page_limit()
    robots_txt = "User-agent: *\nDisallow: /zablokowana-\n"

    sitemap =
      Enum.map_join(
        1..2_000,
        &"<url><loc>#{home}#{Enum.at(["strona", "zablokowana"], rem(&1, 2))}-mapa-#{&1}</loc></url>"
      )

    stub(Dirmoon.WebPageMock, :fetch, fn url ->
      cond do
        url == home <> "robots.txt" ->
          page(url, %{status: 200, content_type: "text/plain", body: robots_txt})

        url == home <> "sitemap.xml" ->
          page(url, %{status: 200, content_type: "application/xml", body: "<urlset>#{sitemap}</urlset>"})

        String.starts_with?(url, home) ->
          page(url, %{status: 200, content_type: "text/html", body: hundred_new_links(url)})

        true ->
          {:error, "connection refused"}
      end
    end)

    %{crawled: {:ok, %SiteScan{pages_read: pages_read, facts: facts}}, robots_checks: robots_checks} =
      count_robots_checks(fn -> crawl(site_scan) end)

    assert pages_read == limit
    assert facts["links_checked"] in 1..100
    assert Enum.count(facts["blocked_pages"]) == 50
    assert robots_checks <= 1 + 2 * limit + 2 * limit + 200
  end

  defp count_robots_checks(crawl) do
    checked_function = {Robots, :allowed?, 2}
    Code.ensure_loaded!(Robots)
    :erlang.trace_pattern(checked_function, true, [:call_count])
    crawled = crawl.()
    {:call_count, robots_checks} = :erlang.trace_info(checked_function, :call_count)
    :erlang.trace_pattern(checked_function, false, [:call_count])

    %{crawled: crawled, robots_checks: robots_checks}
  end

  defp crawl(site_scan) do
    google_not_configured()

    site_scan.id
    |> SiteScans.get_scanning()
    |> Crawler.crawl()
  end

  defp hundred_new_links(url) do
    id = :erlang.phash2(url)
    Enum.map_join(1..50, &~s(<a href="/strona-#{id}-#{&1}">S</a><a href="/zablokowana-#{id}-#{&1}">Z</a>))
  end

  defp page(url, %{status: status, content_type: content_type, body: body}),
    do: {:ok, %{url: url, status: status, redirects: [], content_type: content_type, body: body}}

  defp google_not_configured do
    stub(Dirmoon.PageSpeedMock, :check, fn _request -> {:error, :page_speed_not_configured} end)
    stub(Dirmoon.DataForSEOMock, :indexed_page_count, fn _request -> {:error, :data_for_seo_not_configured} end)
    stub(Dirmoon.DataForSEOMock, :business_profile, fn _request -> {:error, :data_for_seo_not_configured} end)
    stub(Dirmoon.DataForSEOMock, :linking_sites, fn _request -> {:error, :data_for_seo_not_configured} end)
  end
end
