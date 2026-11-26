defmodule Dirmoon.SiteScans.Findings.FindableTest do
  use ExUnit.Case, async: true

  alias Dirmoon.SiteScans.Finding
  alias Dirmoon.SiteScans.Findings.Findable
  alias Dirmoon.SiteScans.ScannedPage

  @home "https://strona-testowa.example/"
  @page_limit 4

  test "a site no address of which answers over https is a problem" do
    assert [%Finding{question: :findable, level: :problem}] = findings(:https, site(%{"https" => false}))
  end

  test "a site answering over https is good news" do
    assert [%Finding{level: :good}] = findings(:https, site(%{"https" => true}))
  end

  test "www and the bare address both answering without a redirect is a warning listing both addresses" do
    facts = %{
      "www_and_bare_both_answer" => true,
      "addresses" => [
        %{"url" => "https://strona-testowa.example/", "status" => 200},
        %{"url" => "https://www.strona-testowa.example/", "status" => 200},
        %{"url" => "http://strona-testowa.example/", "status" => 301}
      ]
    }

    assert [%Finding{level: :warning, figures: %{addresses: addresses}}] = findings(:www_and_bare, site(facts))
    assert addresses == ["https://strona-testowa.example/", "https://www.strona-testowa.example/"]
  end

  test "one of www and the bare address sending to the other is good news" do
    assert [%Finding{level: :good}] = findings(:www_and_bare, site(%{"www_and_bare_both_answer" => false}))
  end

  test "robots.txt blocking the whole site is a problem" do
    facts = %{"robots_txt" => %{"present" => true, "status" => 200, "unreadable" => false, "blocks_site" => true}}

    assert [%Finding{level: :problem, figures: %{present: true, status: 200}}] = findings(:robots_txt, site(facts))
  end

  test "robots.txt that could not be read is a warning" do
    facts = %{"robots_txt" => %{"present" => false, "status" => 503, "unreadable" => true, "blocks_site" => false}}

    assert [%Finding{level: :warning, figures: %{present: false, status: 503}}] = findings(:robots_txt, site(facts))
  end

  test "robots.txt letting Google in is good news" do
    facts = %{"robots_txt" => %{"present" => true, "status" => 200, "unreadable" => false, "blocks_site" => false}}

    assert [%Finding{level: :good}] = findings(:robots_txt, site(facts))
  end

  test "pages asking Google not to list them are a warning listing them" do
    hidden = page("https://strona-testowa.example/ukryta", %{"noindex" => true})

    assert [%Finding{level: :warning, pages: [url], page_count: 1}] =
             findings(:noindex, site(%{}, [page(@home), hidden]))

    assert url == hidden.url
  end

  test "a home page asking Google not to list it is a problem" do
    assert [%Finding{level: :problem, pages: [@home]}] =
             findings(:noindex, site(%{}, [page(@home, %{"noindex" => true})]))
  end

  test "readable pages Google may all list are good news" do
    assert [%Finding{level: :good}] = findings(:noindex, site(%{}, [page(@home)]))
  end

  test "no sitemap is a warning" do
    facts = %{"sitemap" => %{"found" => false, "url" => nil, "page_count" => 0, "pages" => []}}

    assert [%Finding{level: :warning, figures: %{url: nil, page_count: 0}}] = findings(:sitemap, site(facts))
  end

  test "a sitemap is good news with the pages it lists" do
    facts = %{"sitemap" => %{"found" => true, "url" => "https://strona-testowa.example/sitemap.xml", "page_count" => 7}}

    assert [%Finding{level: :good, figures: %{page_count: 7}}] = findings(:sitemap, site(facts))
  end

  test "a broken internal link is a problem listing it with the pages linking to it" do
    facts = %{
      "links_checked" => 3,
      "broken_links" => [
        %{"url" => "https://strona-testowa.example/stara", "status" => 404, "linked_from" => [@home]}
      ]
    }

    assert [
             %Finding{
               level: :problem,
               pages: ["https://strona-testowa.example/stara"],
               figures: %{
                 links_checked: 3,
                 links: [%{url: "https://strona-testowa.example/stara", status: 404, linked_from: [@home]}]
               }
             }
           ] = findings(:broken_links, site(facts))
  end

  test "a broken link whose linking pages aren't a list is listed without them" do
    facts = %{
      "broken_links" => [%{"url" => "https://strona-testowa.example/stara", "status" => 404, "linked_from" => "?"}]
    }

    assert [%Finding{figures: %{links: [%{linked_from: []}]}}] = findings(:broken_links, site(facts))
  end

  test "Scanned Pages answering an error count as broken links" do
    missing = page("https://strona-testowa.example/brak", %{}, %{http_status: 410})

    assert [%Finding{level: :problem, pages: pages}] =
             findings(:broken_links, site(%{"broken_links" => []}, [page(@home), missing]))

    assert pages == [missing.url]
  end

  test "a page whose read failed with no answer is not a broken link but a page I couldn't read" do
    unread = page("https://strona-testowa.example/zawieszona", %{"read_error" => "timeout"}, %{http_status: nil})
    pages = [page(@home), unread]

    assert [%Finding{level: :good}] = findings(:broken_links, site(%{"broken_links" => []}, pages))

    assert [%Finding{level: :warning, pages: [url], figures: %{links: [%{url: url, linked_from: []}]}}] =
             findings(:unreadable_pages, site(%{}, pages))

    assert url == unread.url
  end

  test "a checked link that gave no answer is listed with the pages I couldn't read, not as broken" do
    silent = %{"url" => "https://strona-testowa.example/cisza", "status" => nil, "linked_from" => [@home]}
    facts = %{"broken_links" => [silent], "links_checked" => 1}

    assert [%Finding{level: :good}] = findings(:broken_links, site(facts, [page(@home)]))

    assert [%Finding{level: :warning, pages: ["https://strona-testowa.example/cisza"], figures: %{links: [link]}}] =
             findings(:unreadable_pages, site(facts, [page(@home)]))

    assert link == %{url: "https://strona-testowa.example/cisza", linked_from: [@home]}
  end

  test "every page I tried answering is good news" do
    assert [%Finding{level: :good}] = findings(:unreadable_pages, site(%{}, [page(@home)]))
  end

  test "pages I couldn't read say nothing before any page is read" do
    assert [] = findings(:unreadable_pages, site(%{}))
  end

  test "pages answering 401 or 403 are not counted as broken links" do
    locked = page("https://strona-testowa.example/panel", %{}, %{http_status: 401})

    assert [%Finding{level: :good}] = findings(:broken_links, site(%{"broken_links" => []}, [page(@home), locked]))
  end

  test "no broken link once the links were checked is good news" do
    assert [%Finding{level: :good, figures: %{links_checked: 12}}] =
             findings(:broken_links, site(%{"broken_links" => [], "links_checked" => 12}, [page(@home)]))
  end

  test "broken links say nothing before the links are checked" do
    assert [] = findings(:broken_links, site(%{}, [page(@home)]))
  end

  test "a page reached through two redirects is a warning listing the chain" do
    chained =
      page("https://strona-testowa.example/a", %{
        "redirects" => ["https://strona-testowa.example/a", "https://strona-testowa.example/b"]
      })

    assert [%Finding{level: :warning, pages: [url], figures: %{chains: [%{url: url, redirects: redirects}]}}] =
             findings(
               :redirect_chains,
               site(%{}, [page(@home, %{"redirects" => ["http://strona-testowa.example/"]}), chained])
             )

    assert {url, redirects} == {chained.url, chained.facts["redirects"]}
  end

  test "no redirect chain is good news" do
    assert [%Finding{level: :good}] = findings(:redirect_chains, site(%{}, [page(@home)]))
  end

  test "a page with a password field and little text is a warning" do
    login = page("https://strona-testowa.example/logowanie", %{"password_field" => true, "word_count" => 20})

    assert [%Finding{level: :warning, pages: [url]}] = findings(:password_pages, site(%{}, [page(@home), login]))
    assert url == login.url
  end

  test "a page answering 403 asks for a password" do
    locked = page("https://strona-testowa.example/panel", %{}, %{http_status: 403})

    assert [%Finding{level: :warning, pages: [url]}] = findings(:password_pages, site(%{}, [page(@home), locked]))
    assert url == locked.url
  end

  test "a long page with a password field does not count as asking for a password" do
    shop = page("https://strona-testowa.example/sklep", %{"password_field" => true, "word_count" => 900})

    assert [%Finding{level: :good}] = findings(:password_pages, site(%{}, [page(@home), shop]))
  end

  test "pages robots.txt keeps Google out of are a warning listing them" do
    blocked = ["https://strona-testowa.example/admin"]

    assert [%Finding{level: :warning, pages: ^blocked}] = findings(:blocked_pages, site(%{"blocked_pages" => blocked}))
  end

  test "no page kept out by robots.txt is good news" do
    assert [%Finding{level: :good}] = findings(:blocked_pages, site(%{"blocked_pages" => []}))
  end

  test "Google listing about as many pages as the scan found is good news with both counts" do
    facts = %{"indexed_pages" => %{"checked" => true, "count" => 2}}

    assert [%Finding{level: :good, figures: %{indexed_count: 2, pages_read: 2, page_limit_reached: false}}] =
             findings(:indexed_pages, site(facts, [page(@home), page("https://strona-testowa.example/o-nas")]))
  end

  test "Google listing fewer than half the pages the scan found is a warning" do
    facts = %{"indexed_pages" => %{"checked" => true, "count" => 1}}
    pages = for number <- 1..3, do: page("https://strona-testowa.example/strona-#{number}")

    assert [%Finding{level: :warning, figures: %{indexed_count: 1, pages_read: 3}}] =
             findings(:indexed_pages, site(facts, pages))
  end

  test "no page on Google is a problem" do
    facts = %{"indexed_pages" => %{"checked" => true, "count" => 0}}

    assert [%Finding{level: :problem, figures: %{indexed_count: 0}}] =
             findings(:indexed_pages, site(facts, [page(@home)]))
  end

  test "Google listing fewer than half the pages read is a warning even when the scan read as many pages as it may" do
    facts = %{"indexed_pages" => %{"checked" => true, "count" => 1}}
    pages = for number <- 1..@page_limit, do: page("https://strona-testowa.example/strona-#{number}")

    assert [%Finding{level: :warning, figures: %{indexed_count: 1, pages_read: 4, page_limit_reached: true}}] =
             findings(:indexed_pages, site(facts, pages))
  end

  test "Google listing at least half the pages read can't be judged when the scan read as many pages as it may" do
    facts = %{"indexed_pages" => %{"checked" => true, "count" => 3}}
    pages = for number <- 1..@page_limit, do: page("https://strona-testowa.example/strona-#{number}")

    assert [
             %Finding{
               level: :not_checked,
               figures: %{indexed_count: 3, pages_read: 4, page_limit_reached: true, reason: "page_limit_reached"}
             }
           ] = findings(:indexed_pages, site(facts, pages))
  end

  test "an indexed count not checked says why" do
    facts = %{"indexed_pages" => %{"checked" => false, "reason" => "not_configured"}}

    assert [%Finding{level: :not_checked, figures: %{reason: "not_configured"}}] = findings(:indexed_pages, site(facts))
  end

  test "a scan that stored nothing yet has no Findable Finding" do
    assert [] = Findable.check(site(%{}))
  end

  defp findings(check, site), do: site |> Findable.check() |> Enum.filter(&(&1.check == check))

  defp site(facts, pages \\ []),
    do: %{facts: facts, pages: pages, home_page: @home, niches: [], phrases: [], page_limit: @page_limit}

  defp page(url, facts \\ %{}, attributes \\ %{}) do
    struct(
      %ScannedPage{url: url, http_status: 200, facts: Map.merge(%{"word_count" => 400, "final_url" => url}, facts)},
      attributes
    )
  end
end
