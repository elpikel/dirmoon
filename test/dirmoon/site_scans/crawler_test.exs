defmodule Dirmoon.SiteScans.CrawlerTest do
  use Dirmoon.DataCase, async: true

  import Mox

  alias Dirmoon.Competition.SerpSnapshot
  alias Dirmoon.Phrases.Metrics
  alias Dirmoon.Phrases.Phrase
  alias Dirmoon.SiteScans
  alias Dirmoon.SiteScans.Crawler
  alias Dirmoon.SiteScans.ScannedPage
  alias Dirmoon.SiteScans.SiteScan
  alias Dirmoon.WebPage

  test "the home page is read first and stored with its Page Facts, where it ended up and its content type" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    serve(%{home => html_page(home, "<html lang=\"pl\"><title>Kancelaria</title><h1>Witamy</h1></html>")})

    assert {:ok, %SiteScan{pages_read: 1}} = crawl(site_scan)

    assert [
             %ScannedPage{
               url: ^home,
               http_status: 200,
               position: 1,
               facts: %{
                 "title" => "Kancelaria",
                 "main_headings" => ["Witamy"],
                 "language" => "pl",
                 "final_url" => ^home,
                 "redirects" => [],
                 "content_type" => "text/html"
               }
             }
           ] = scanned_pages(site_scan)
  end

  test "pages linked from the home page are read breadth-first" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)

    serve(%{
      home => html_page(home, ~s(<a href="/oferta">Oferta</a><a href="/kontakt">Kontakt</a>)),
      (home <> "oferta") => html_page(home <> "oferta", ~s(<a href="/oferta/porady">Porady</a>)),
      (home <> "kontakt") => html_page(home <> "kontakt", "<p>Kontakt</p>"),
      (home <> "oferta/porady") => html_page(home <> "oferta/porady", "<p>Porady</p>")
    })

    {:ok, _site_scan} = crawl(site_scan)

    assert Enum.map(scanned_pages(site_scan), &{&1.position, &1.url}) == [
             {1, home},
             {2, home <> "oferta"},
             {3, home <> "kontakt"},
             {4, home <> "oferta/porady"}
           ]
  end

  test "the crawl stops at the page limit and the home page comes first" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    links = Enum.map_join(1..(SiteScans.page_limit() + 10), &~s(<a href="/strona-#{&1}">#{&1}</a>))
    serve(%{home => html_page(home, links)}, fn url -> html_page(url, "<p>Strona</p>") end)

    assert {:ok, %SiteScan{pages_read: pages_read}} = crawl(site_scan)

    pages = scanned_pages(site_scan)
    assert pages_read == SiteScans.page_limit()
    assert Enum.count(pages) == SiteScans.page_limit()
    assert hd(pages).url == home
  end

  test "pages on other hosts are not read, and the www address counts as the same site" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    www_page = "https://www.#{site_scan.run.domain}/galeria"

    serve(%{
      home => html_page(home, ~s(<a href="https://inna-strona.example/">Inna</a><a href="#{www_page}">Galeria</a>
          <a href="mailto:biuro@#{site_scan.run.domain}">E-mail</a><a href="http://localhost/admin">Admin</a>)),
      www_page => html_page(www_page, "<p>Galeria</p>")
    })

    {:ok, _site_scan} = crawl(site_scan)

    assert Enum.map(scanned_pages(site_scan), & &1.url) == [home, www_page]
    refute_received {:fetched, "https://inna-strona.example/"}
    refute_received {:fetched, "http://localhost/admin"}
  end

  test "a link to an international site written in its Unicode form counts as the site and is read once" do
    site_scan = insert(:site_scan, run: build(:run, mode: :existing_site, domain: "xn--w-uga1v8h.pl"))
    home = home_url(site_scan)
    offer = "https://xn--w-uga1v8h.pl/oferta"

    serve(%{
      home => html_page(home, ~s(<a href="https://żółw.pl/oferta">1</a><a href="https://ŻÓŁW.pl/oferta">2</a>)),
      offer => html_page(offer, ~s(<a href="https://Żółw.pl/">3</a><a href="https://münchen.de/">4</a>))
    })

    {:ok, _site_scan} = crawl(site_scan)

    assert Enum.map(scanned_pages(site_scan), & &1.url) == [home, offer]
    refute_received {:fetched, "https://xn--mnchen-3ya.de/"}
  end

  test "the same page linked under different spellings is read once" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    upper_case = "HTTPS://#{String.upcase(site_scan.run.domain)}/oferta"

    serve(%{
      home =>
        html_page(
          home,
          ~s(<a href="/oferta#cennik">1</a><a href="/oferta">2</a><a href="#{upper_case}">3</a><a href="https://#{site_scan.run.domain}">4</a>)
        ),
      (home <> "oferta") => html_page(home <> "oferta", ~s(<a href="https://#{site_scan.run.domain}:443/oferta">4</a>))
    })

    {:ok, _site_scan} = crawl(site_scan)

    assert Enum.map(scanned_pages(site_scan), & &1.url) == [home, home <> "oferta"]
  end

  test "a page that redirects is stored under the address asked for, with the addresses it was sent through" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    moved = home <> "stara-oferta"
    final = home <> "oferta/"

    serve(%{
      home => html_page(home, ~s(<a href="/stara-oferta">Oferta</a>)),
      moved =>
        {:ok,
         %{
           url: final,
           status: 200,
           redirects: [moved, home <> "oferta"],
           content_type: "text/html",
           body: ~s(<a href="/oferta/">Oferta</a>)
         }}
    })

    {:ok, _site_scan} = crawl(site_scan)

    assert [_home, %ScannedPage{url: ^moved, facts: %{"final_url" => ^final, "redirects" => [^moved, _middle]}}] =
             scanned_pages(site_scan)

    refute_received {:fetched, ^final}
  end

  test "a page that can't be read is stored with the reason and the crawl carries on" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)

    serve(%{
      home => html_page(home, ~s(<a href="/zepsuta">1</a><a href="/oferta">2</a>)),
      (home <> "zepsuta") => {:error, "the page took too long to read"},
      (home <> "oferta") => html_page(home <> "oferta", "<p>Oferta</p>")
    })

    assert {:ok, %SiteScan{pages_read: 3}} = crawl(site_scan)

    assert [
             _home,
             %ScannedPage{http_status: nil, facts: %{"read_error" => "the page took too long to read"}},
             %ScannedPage{http_status: 200}
           ] = scanned_pages(site_scan)
  end

  test "a page whose read crashes is stored as unreadable and the crawl carries on" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)

    serve(
      %{
        home => html_page(home, ~s(<a href="/zepsuta">1</a><a href="/oferta">2</a>)),
        (home <> "oferta") => html_page(home <> "oferta", "<p>Oferta</p>")
      },
      fn url -> if String.ends_with?(url, "/zepsuta"), do: raise("the reader broke"), else: html_page(url, 404, "") end
    )

    assert {:ok, %SiteScan{pages_read: 3}} = crawl(site_scan)

    assert [_home, %ScannedPage{http_status: nil, facts: %{"read_error" => "the page could not be read"}}, _oferta] =
             scanned_pages(site_scan)
  end

  test "a link that is redirected to a private address is stored as unreadable and that address is never requested" do
    site_scan = insert(:site_scan)
    test_pid = self()

    stub(Dirmoon.WebPageMock, :fetch, &WebPage.HTTP.fetch/1)

    Req.Test.stub(WebPage.HTTP, fn conn ->
      send(test_pid, {:requested, conn.host, conn.request_path})

      case conn.request_path do
        "/" ->
          conn |> Plug.Conn.put_resp_content_type("text/html") |> Plug.Conn.send_resp(200, ~s(<a href="/panel">P</a>))

        "/panel" ->
          conn |> Plug.Conn.put_resp_header("location", "http://10.0.0.5/") |> Plug.Conn.send_resp(302, "")

        _other ->
          Plug.Conn.send_resp(conn, 404, "")
      end
    end)

    {:ok, _site_scan} = crawl(site_scan)

    assert [_home, %ScannedPage{http_status: nil, facts: %{"read_error" => "an address in a private network"}}] =
             scanned_pages(site_scan)

    refute_received {:requested, "10.0.0.5", _path}
  end

  test "an answer that is not a web page is stored with its status and content type but no Page Facts" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    pdf = home <> "cennik.pdf"

    serve(%{
      home => html_page(home, ~s(<a href="/cennik.pdf">Cennik</a>)),
      pdf => {:ok, %{url: pdf, status: 200, redirects: [], content_type: "application/pdf", body: ""}}
    })

    {:ok, _site_scan} = crawl(site_scan)

    assert [_home, %ScannedPage{http_status: 200, facts: facts}] = scanned_pages(site_scan)
    assert facts == %{"final_url" => pdf, "redirects" => [], "content_type" => "application/pdf"}
  end

  test "a page without a content type is stored with none, and a long content type is kept to 255 bytes" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    long_type = "text/" <> String.duplicate("x", 300)

    serve(%{
      home => html_page(home, ~s(<a href="/plik">P</a><a href="/inny">I</a>)),
      (home <> "plik") => answer(home <> "plik", %{status: 200, content_type: nil, body: ""}),
      (home <> "inny") => answer(home <> "inny", %{status: 200, content_type: long_type, body: ""})
    })

    {:ok, _site_scan} = crawl(site_scan)

    assert [_home, %ScannedPage{facts: %{"content_type" => nil}}, %ScannedPage{facts: %{"content_type" => kept}}] =
             scanned_pages(site_scan)

    assert kept == binary_part(long_type, 0, 255)
  end

  test "links on a page that answered with an error are not followed" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)

    serve(%{
      home => html_page(home, ~s(<a href="/brak">Brak</a>)),
      (home <> "brak") => html_page(home <> "brak", 404, ~s(<a href="/ukryta">Ukryta</a>))
    })

    {:ok, _site_scan} = crawl(site_scan)

    assert [_home, %ScannedPage{http_status: 404}] = scanned_pages(site_scan)
    hidden = home <> "ukryta"
    refute_received {:fetched, ^hidden}
  end

  test "a page listed only in the sitemap is read after the linked pages" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    hidden = home <> "ukryta"

    serve(%{
      home => html_page(home, ~s(<a href="/oferta">Oferta</a>)),
      (home <> "oferta") => html_page(home <> "oferta", "<p>Oferta</p>"),
      (home <> "sitemap.xml") => xml_page(home <> "sitemap.xml", urlset([home, hidden])),
      hidden => html_page(hidden, "<p>Ukryta</p>")
    })

    {:ok, %SiteScan{facts: facts}} = crawl(site_scan)

    assert Enum.map(scanned_pages(site_scan), & &1.url) == [home, home <> "oferta", hidden]
    assert %{"found" => true, "url" => sitemap_url, "page_count" => 2} = facts["sitemap"]
    assert sitemap_url == home <> "sitemap.xml"
  end

  test "the sitemaps robots.txt names are read instead of the usual address, nested sitemaps included" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    index = home <> "mapa.xml"
    nested = Enum.map(1..8, &"#{home}mapa-#{&1}.xml")

    serve(
      %{
        home => html_page(home, "<p>Start</p>"),
        (home <> "robots.txt") => text_page(home <> "robots.txt", "Sitemap: #{index}\n"),
        index =>
          xml_page(index, "<sitemapindex>#{Enum.map_join(nested, &"<sitemap><loc>#{&1}</loc></sitemap>")}</sitemapindex>")
      },
      fn url -> xml_page(url, urlset([String.replace_suffix(url, ".xml", "")])) end
    )

    {:ok, %SiteScan{facts: facts}} = crawl(site_scan)

    assert %{"found" => true, "url" => ^index, "page_count" => 4} = facts["sitemap"]
    sitemap_at_usual_address = home <> "sitemap.xml"
    fifth_nested = home <> "mapa-5.xml"
    refute_received {:fetched, ^sitemap_at_usual_address}
    refute_received {:fetched, ^fifth_nested}
  end

  test "a site without a sitemap is noted as having none" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    serve(%{home => html_page(home, "<p>Start</p>")})

    {:ok, %SiteScan{facts: facts}} = crawl(site_scan)

    assert facts["sitemap"] == %{"found" => false, "url" => nil, "page_count" => 0, "pages" => []}
  end

  test "pages robots.txt disallows are not requested and are noted as blocked" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)

    serve(%{
      home =>
        html_page(
          home,
          ~s(<a href="/panel/logowanie">Panel</a><a href="/oferta">Oferta</a><a href="/oferta?sort=cena">C</a>)
        ),
      (home <> "robots.txt") => text_page(home <> "robots.txt", "User-agent: *\nDisallow: /panel\nDisallow: /*?sort=\n"),
      (home <> "oferta") => html_page(home <> "oferta", "<p>Oferta</p>")
    })

    {:ok, %SiteScan{facts: facts}} = crawl(site_scan)

    assert Enum.map(scanned_pages(site_scan), & &1.url) == [home, home <> "oferta"]
    assert facts["blocked_pages"] == [home <> "panel/logowanie", home <> "oferta?sort=cena"]
    blocked = home <> "panel/logowanie"
    refute_received {:fetched, ^blocked}

    assert %{"present" => true, "status" => 200, "unreadable" => false, "blocks_site" => false, "sitemaps" => []} =
             facts["robots_txt"]
  end

  test "an unread link robots.txt disallows is noted as blocked and not requested when the links are checked" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    limit = SiteScans.page_limit()
    links = Enum.map_join(1..limit, &~s(<a href="/strona-#{&1}">S</a>)) <> ~s(<a href="/panel">P</a>)
    blocked = home <> "panel"

    serve(
      %{
        home => html_page(home, links),
        (home <> "robots.txt") => text_page(home <> "robots.txt", "User-agent: *\nDisallow: /panel\n")
      },
      fn url -> html_page(url, "<p>Strona</p>") end
    )

    {:ok, %SiteScan{facts: facts}} = crawl(site_scan)

    assert facts["blocked_pages"] == [blocked]
    assert facts["links_checked"] == 1
    refute_received {:fetched, ^blocked}
  end

  test "a robots.txt with a byte that is not UTF-8 and a page with a NUL character in its structured data are stored" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    json_ld = ~s(<script type="application/ld+json">{"@type": "Hotel", "name": "A\\u0000B"}</script>)

    serve(%{
      home => html_page(home, json_ld <> ~s(<a href="/oferta">O</a>)),
      (home <> "robots.txt") => text_page(home <> "robots.txt", "User-agent: *\nDisallow: /k\xF3d\n"),
      (home <> "oferta") => html_page(home <> "oferta", "<p>Oferta</p>")
    })

    assert {:ok, %SiteScan{pages_read: 2, facts: facts}} = crawl(site_scan)

    assert %{"present" => true, "blocks_site" => false} = facts["robots_txt"]
    assert [%ScannedPage{facts: %{"business_name" => "AB"}}, _oferta] = scanned_pages(site_scan)
  end

  test "a robots.txt that disallows the whole site leaves every page unread and says so" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)

    serve(%{
      home => html_page(home, ~s(<a href="/oferta">Oferta</a>)),
      (home <> "robots.txt") => text_page(home <> "robots.txt", "User-agent: *\nDisallow: /\n")
    })

    assert {:ok, %SiteScan{pages_read: 0, facts: facts}} = crawl(site_scan)

    assert scanned_pages(site_scan) == []
    assert %{"blocks_site" => true} = facts["robots_txt"]
    assert facts["blocked_pages"] == [home]
  end

  test "a missing robots.txt allows everything and is noted as missing" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    serve(%{home => html_page(home, "<p>Start</p>")})

    {:ok, %SiteScan{facts: facts}} = crawl(site_scan)

    assert %{"present" => false, "status" => 404, "unreadable" => false, "blocks_site" => false} = facts["robots_txt"]
  end

  test "a robots.txt that answers with a server error is noted as unreadable and everything is read" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)

    serve(%{
      home => html_page(home, ~s(<a href="/oferta">Oferta</a>)),
      (home <> "robots.txt") => text_page(home <> "robots.txt", 503, "Disallow: /"),
      (home <> "oferta") => html_page(home <> "oferta", "<p>Oferta</p>")
    })

    {:ok, %SiteScan{facts: facts}} = crawl(site_scan)

    assert Enum.count(scanned_pages(site_scan)) == 2
    assert %{"present" => false, "status" => 503, "unreadable" => true, "blocks_site" => false} = facts["robots_txt"]
  end

  test "a robots.txt that can't be read is noted as unreadable" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    serve(%{home => html_page(home, "<p>Start</p>"), (home <> "robots.txt") => {:error, "too many redirects"}})

    {:ok, %SiteScan{facts: facts}} = crawl(site_scan)

    assert %{"present" => false, "status" => nil, "unreadable" => true} = facts["robots_txt"]
  end

  test "the address variants are noted: which answer, where they end up and whether https works" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    www = "https://www.#{site_scan.run.domain}/"
    http = "http://#{site_scan.run.domain}/"
    http_www = "http://www.#{site_scan.run.domain}/"

    serve(%{
      home => html_page(home, "<p>Start</p>"),
      www => {:ok, %{url: home, status: 200, redirects: [www], content_type: "text/html", body: ""}},
      http => {:ok, %{url: home, status: 200, redirects: [http], content_type: "text/html", body: ""}},
      http_www => {:error, "connection refused"}
    })

    {:ok, %SiteScan{facts: facts}} = crawl(site_scan)

    assert %{"home_page" => ^home, "https" => true, "www_and_bare_both_answer" => false} = facts

    assert facts["addresses"] == [
             %{"url" => home, "status" => 200, "final_url" => home, "redirects" => [], "error" => nil},
             %{"url" => www, "status" => 200, "final_url" => home, "redirects" => [www], "error" => nil},
             %{"url" => http, "status" => 200, "final_url" => home, "redirects" => [http], "error" => nil},
             %{"url" => http_www, "status" => nil, "final_url" => nil, "redirects" => [], "error" => "connection refused"}
           ]
  end

  test "www and bare addresses that both answer without redirecting to each other are noted" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    www = "https://www.#{site_scan.run.domain}/"
    serve(%{home => html_page(home, "<p>Start</p>"), www => html_page(www, "<p>Start</p>")})

    {:ok, %SiteScan{facts: facts}} = crawl(site_scan)

    assert facts["www_and_bare_both_answer"] == true
  end

  test "a site that answers only over http is read there and https is noted as not working" do
    site_scan = insert(:site_scan)
    http = "http://#{site_scan.run.domain}/"

    serve(%{http => html_page(http, "<p>Start</p>")}, fn
      "https://" <> _rest -> {:error, "connection refused"}
      url -> html_page(url, 404, "")
    end)

    {:ok, %SiteScan{facts: facts}} = crawl(site_scan)

    assert %{"home_page" => ^http, "https" => false} = facts
    assert [%ScannedPage{url: ^http}] = scanned_pages(site_scan)
  end

  test "a home page on the www address is where the crawl starts" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    www = "https://www.#{site_scan.run.domain}/"

    serve(%{
      home => {:ok, %{url: www, status: 200, redirects: [home], content_type: "text/html", body: ~s(<a href="/o">O</a>)}},
      (www <> "o") => html_page(www <> "o", "<p>O</p>")
    })

    {:ok, %SiteScan{facts: facts}} = crawl(site_scan)

    assert facts["home_page"] == www
    assert Enum.map(scanned_pages(site_scan), & &1.url) == [www, www <> "o"]
    robots_on_bare_host = home <> "robots.txt"
    refute_received {:fetched, ^robots_on_bare_host}
  end

  test "a site that can't be opened is an error and nothing is stored" do
    site_scan = insert(:site_scan)
    serve(%{}, fn url -> html_page(url, 500, "") end)

    assert {:error, "The site could not be opened: none of its addresses answered with a page"} = crawl(site_scan)

    assert scanned_pages(site_scan) == []
    assert Repo.reload!(site_scan).facts == %{}
  end

  test "a resumed crawl never requests a stored page or the site facts again, robots.txt aside, and goes on from the stored pages' links" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)

    stored_site_scan =
      site_scan
      |> Ecto.Changeset.change(pages_read: 1, facts: stored_site_facts(home))
      |> Repo.update!()

    insert(:scanned_page,
      site_scan: stored_site_scan,
      url: home,
      position: 1,
      facts: %{"internal_links" => [home <> "oferta"], "final_url" => home}
    )

    serve(%{(home <> "oferta") => html_page(home <> "oferta", "<p>Oferta</p>")})

    assert {:ok, %SiteScan{pages_read: 2}} = crawl(stored_site_scan)

    assert Enum.map(scanned_pages(site_scan), &{&1.position, &1.url}) == [{1, home}, {2, home <> "oferta"}]
    oferta = home <> "oferta"
    robots_txt = home <> "robots.txt"
    assert_received {:fetched, ^robots_txt}
    assert_received {:fetched, ^oferta}
    refute_received {:fetched, _any_other_url}
  end

  test "a resumed crawl reads robots.txt again and keeps to its rules" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    blocked = home <> "panel"

    stored_site_scan =
      site_scan
      |> Ecto.Changeset.change(pages_read: 1, facts: stored_site_facts(home))
      |> Repo.update!()

    insert(:scanned_page,
      site_scan: stored_site_scan,
      url: home,
      position: 1,
      facts: %{"internal_links" => [blocked], "final_url" => home}
    )

    serve(%{(home <> "robots.txt") => text_page(home <> "robots.txt", "User-agent: *\nDisallow: /panel\n")})

    assert {:ok, %SiteScan{pages_read: 1, facts: facts}} = crawl(stored_site_scan)

    assert facts["blocked_pages"] == [blocked]
    assert %{"present" => true, "blocks_site" => false} = facts["robots_txt"]
    refute_received {:fetched, ^blocked}
  end

  test "robots.txt's rules are not stored and at most ten of its sitemaps are" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    sitemap_lines = Enum.map_join(1..12, &"Sitemap: #{home}mapa-#{&1}.xml\n")

    serve(%{
      home => html_page(home, "<p>Start</p>"),
      (home <> "robots.txt") => text_page(home <> "robots.txt", "User-agent: *\nDisallow: /panel\n" <> sitemap_lines)
    })

    {:ok, %SiteScan{facts: facts}} = crawl(site_scan)

    assert facts["robots_txt"] == %{
             "present" => true,
             "status" => 200,
             "unreadable" => false,
             "blocks_site" => false,
             "sitemaps" => Enum.map(1..10, &"#{home}mapa-#{&1}.xml")
           }
  end

  test "subscribers are told as pages are stored and pages read is kept up to date" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    run_id = site_scan.run_id
    serve(%{home => html_page(home, "<p>Start</p>")})
    :ok = SiteScans.subscribe(site_scan.run)

    {:ok, _site_scan} = crawl(site_scan)

    assert_received {:site_scan_updated, ^run_id}
    assert %SiteScan{pages_read: 1} = Repo.reload!(site_scan)
  end

  test "internal links found but not read are checked and the broken ones noted with the pages linking to them" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    limit = SiteScans.page_limit()
    links = Enum.map_join(1..(limit + 1), &~s(<a href="/strona-#{&1}">#{&1}</a>))
    unread = "#{home}strona-#{limit}"
    unread_broken = "#{home}strona-#{limit + 1}"

    serve(%{home => html_page(home, links), unread_broken => html_page(unread_broken, 410, "")}, fn url ->
      html_page(url, "<p>Strona</p>")
    end)

    {:ok, %SiteScan{facts: facts}} = crawl(site_scan)

    assert facts["links_checked"] == 2
    assert facts["broken_links"] == [%{"url" => unread_broken, "status" => 410, "linked_from" => [home]}]
    assert_received {:fetched, ^unread}
  end

  test "an unread link that can't be opened is noted as broken without a status, with at most three pages linking to it" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    limit = SiteScans.page_limit()
    pages = Enum.map(1..(limit - 1), &"#{home}strona-#{&1}")
    unreadable = home <> "zepsuta"

    serve(
      %{home => html_page(home, Enum.map_join(pages, &~s(<a href="#{&1}">S</a>))), unreadable => {:error, "timeout"}},
      fn url -> html_page(url, ~s(<a href="/zepsuta">Z</a>)) end
    )

    {:ok, %SiteScan{facts: facts}} = crawl(site_scan)

    assert [%{"url" => ^unreadable, "status" => nil, "linked_from" => linked_from}] = facts["broken_links"]
    assert linked_from == Enum.take(pages, 3)
  end

  test "an unread link whose check crashes is noted as broken without a status" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    limit = SiteScans.page_limit()
    links = Enum.map_join(1..limit, &~s(<a href="/strona-#{&1}">#{&1}</a>))
    unread = "#{home}strona-#{limit}"

    serve(%{home => html_page(home, links)}, fn
      ^unread -> raise "the reader broke"
      url -> html_page(url, "<p>Strona</p>")
    end)

    {:ok, %SiteScan{facts: facts}} = crawl(site_scan)

    assert facts["broken_links"] == [%{"url" => unread, "status" => nil, "linked_from" => [home]}]
  end

  test "at most a hundred unread links are checked" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    links = Enum.map_join(1..(SiteScans.page_limit() + 50), &~s(<a href="/strona-#{&1}">#{&1}</a>))

    serve(%{home => html_page(home, links)}, fn url ->
      html_page(url, ~s(<a href="#{url}/dalej-1">1</a><a href="#{url}/dalej-2">2</a>))
    end)

    {:ok, %SiteScan{facts: facts}} = crawl(site_scan)

    assert facts["links_checked"] == 100
    assert facts["broken_links"] == []
  end

  test "a finished crawl leaves the shared market tables unchanged" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    serve(%{home => html_page(home, ~s(<a href="/oferta">Oferta</a>))}, fn url -> html_page(url, "<p>O</p>") end)
    before = shared_row_counts()

    {:ok, _site_scan} = crawl(site_scan)

    assert shared_row_counts() == before
  end

  test "a page whose read ends on another host is stored without Page Facts and its links are not followed" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    moved = home <> "sklep"
    other_site = "https://inny-sklep.example/"
    hidden = home <> "ukryta"

    serve(%{
      home => html_page(home, ~s(<a href="/sklep">Sklep</a>)),
      moved =>
        {:ok,
         %{
           url: other_site,
           status: 200,
           redirects: [moved],
           content_type: "text/html",
           body: ~s(<title>Inny sklep</title><a href="#{hidden}">Ukryta</a>)
         }}
    })

    {:ok, _site_scan} = crawl(site_scan)

    assert [_home, %ScannedPage{url: ^moved, http_status: 200, facts: facts}] = scanned_pages(site_scan)

    assert facts == %{
             "off_site" => true,
             "final_url" => other_site,
             "redirects" => [moved],
             "content_type" => "text/html"
           }

    refute_received {:fetched, ^hidden}
  end

  test "a page whose read ends on the site's host in another spelling keeps its Page Facts" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    moved = home <> "stara"
    final = "https://WWW.#{String.upcase(site_scan.run.domain)}/nowa"

    serve(%{
      home => html_page(home, ~s(<a href="/stara">Stara</a>)),
      moved =>
        {:ok, %{url: final, status: 200, redirects: [moved], content_type: "text/html", body: "<title>Nowa</title>"}}
    })

    {:ok, _site_scan} = crawl(site_scan)

    assert [_home, %ScannedPage{url: ^moved, facts: %{"title" => "Nowa"} = facts}] = scanned_pages(site_scan)
    refute Map.has_key?(facts, "off_site")
  end

  test "the sitemap's pages on other hosts are neither counted nor kept, and the www host counts as the site" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    www_page = "https://www.#{site_scan.run.domain}/galeria"

    serve(%{
      home => html_page(home, "<p>Start</p>"),
      (home <> "sitemap.xml") =>
        xml_page(home <> "sitemap.xml", urlset([home, "https://inna-strona.example/", www_page, home <> "#gora"]))
    })

    {:ok, %SiteScan{facts: facts}} = crawl(site_scan)

    assert %{"found" => true, "page_count" => 2, "pages" => [^home, ^www_page]} = facts["sitemap"]
    refute_received {:fetched, "https://inna-strona.example/"}
  end

  test "a sitemap longer than the crawl can take is counted in full but keeps only twice the page limit" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    limit = SiteScans.page_limit()
    listed = Enum.map(1..(limit * 3), &"#{home}strona-#{&1}")

    serve(%{
      home => html_page(home, "<p>Start</p>"),
      (home <> "sitemap.xml") => xml_page(home <> "sitemap.xml", urlset(listed))
    })

    {:ok, %SiteScan{facts: facts}} = crawl(site_scan)

    assert facts["sitemap"]["page_count"] == limit * 3
    assert facts["sitemap"]["pages"] == Enum.take(listed, limit * 2)
  end

  test "the sitemap's pages kept for the crawl fit in 64 KiB together" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    listed = Enum.map(1..100, &"#{home}#{String.duplicate("s", 1_000)}-#{&1}")

    serve(%{
      home => html_page(home, "<p>Start</p>"),
      (home <> "sitemap.xml") => xml_page(home <> "sitemap.xml", urlset(listed))
    })

    {:ok, %SiteScan{facts: facts}} = crawl(site_scan)

    kept = facts["sitemap"]["pages"]
    assert kept == Enum.take(listed, length(kept))
    assert kept |> Enum.map(&byte_size/1) |> Enum.sum() <= 65_536
    assert listed |> Enum.take(length(kept) + 1) |> Enum.map(&byte_size/1) |> Enum.sum() > 65_536
    assert facts["sitemap"]["page_count"] == 100
  end

  test "the blocked pages kept fit in 32 KiB together" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    blocked = Enum.map(1..30, &"#{home}panel/#{String.duplicate("p", 1_900)}-#{&1}")

    serve(%{
      home => html_page(home, Enum.map_join(blocked, &~s(<a href="#{&1}">P</a>))),
      (home <> "robots.txt") => text_page(home <> "robots.txt", "User-agent: *\nDisallow: /panel\n")
    })

    {:ok, %SiteScan{facts: facts}} = crawl(site_scan)

    kept = facts["blocked_pages"]
    assert kept == Enum.take(blocked, length(kept))
    assert kept |> Enum.map(&byte_size/1) |> Enum.sum() <= 32_768
    assert length(kept) < length(blocked)
  end

  test "the broken links kept fit in 64 KiB of addresses together, each with at most three pages linking to it" do
    site_scan = insert(:site_scan)
    home = home_url(site_scan)
    limit = SiteScans.page_limit()
    pages = Enum.map(1..(limit - 1), &"#{home}strona-#{&1}")

    serve(%{home => html_page(home, Enum.map_join(pages, &~s(<a href="#{&1}">S</a>)))}, fn url ->
      if String.contains?(url, "zepsuta-") do
        html_page(url, 404, "")
      else
        links = Enum.map_join(1..3, &~s(<a href="#{url}/zepsuta-#{String.duplicate("z", 1_000)}-#{&1}">Z</a>))
        html_page(url, links)
      end
    end)

    {:ok, %SiteScan{facts: facts}} = crawl(site_scan)

    broken = facts["broken_links"]
    assert facts["links_checked"] == 100
    assert length(broken) in 1..99
    assert Enum.all?(broken, &(Enum.count_until(&1["linked_from"], 4) <= 3))

    assert broken
           |> Enum.map(
             &(byte_size(&1["url"]) + (&1["linked_from"] |> Enum.map(fn page -> byte_size(page) end) |> Enum.sum()))
           )
           |> Enum.sum() <= 65_536
  end

  test "killing the crawl's process ends the reads it started" do
    site_scan = insert(:site_scan)
    test_pid = self()

    stub(Dirmoon.WebPageMock, :fetch, &WebPage.HTTP.fetch/1)

    Req.Test.stub(WebPage.HTTP, fn conn ->
      case conn.request_path do
        "/" ->
          conn |> Plug.Conn.put_resp_content_type("text/html") |> Plug.Conn.send_resp(200, ~s(<a href="/wolna">W</a>))

        "/wolna" ->
          send(test_pid, {:reading, %{read: self(), reader: hd(Process.get(:"$callers"))}})

          receive do
            :never -> conn
          end

        _other ->
          Plug.Conn.send_resp(conn, 404, "")
      end
    end)

    {:ok, crawl_process} = Task.start(fn -> crawl(site_scan) end)

    assert_receive {:reading, %{read: read, reader: reader}}, 5_000
    read_ref = Process.monitor(read)
    reader_ref = Process.monitor(reader)

    Process.exit(crawl_process, :kill)

    assert_receive {:DOWN, ^reader_ref, :process, ^reader, :killed}, 5_000
    assert_receive {:DOWN, ^read_ref, :process, ^read, :killed}, 5_000
  end

  defp crawl(site_scan) do
    google_not_configured()

    site_scan.id
    |> SiteScans.get_scanning()
    |> Crawler.crawl()
  end

  defp scanned_pages(site_scan) do
    ScannedPage
    |> from(as: :scanned_page)
    |> where([scanned_page: scanned_page], scanned_page.site_scan_id == ^site_scan.id)
    |> order_by([scanned_page: scanned_page], scanned_page.position)
    |> Repo.all()
  end

  defp home_url(site_scan), do: "https://#{site_scan.run.domain}/"

  defp serve(answers, otherwise \\ fn url -> html_page(url, 404, "") end) do
    test_pid = self()

    stub(Dirmoon.WebPageMock, :fetch, fn url ->
      send(test_pid, {:fetched, url})
      answer_for(url, %{answers: answers, otherwise: otherwise})
    end)
  end

  defp answer_for(url, %{answers: answers, otherwise: otherwise}) do
    cond do
      Map.has_key?(answers, url) -> Map.fetch!(answers, url)
      variant?(url) -> {:error, "connection refused"}
      true -> otherwise.(url)
    end
  end

  defp variant?(url), do: Regex.match?(~r{^https?://[^/]+/$}, url)

  defp html_page(url, status \\ 200, html), do: answer(url, %{status: status, content_type: "text/html", body: html})

  defp text_page(url, status \\ 200, text), do: answer(url, %{status: status, content_type: "text/plain", body: text})

  defp xml_page(url, xml), do: answer(url, %{status: 200, content_type: "application/xml", body: xml})

  defp answer(url, %{status: status, content_type: content_type, body: body}),
    do: {:ok, %{url: url, status: status, redirects: [], content_type: content_type, body: body}}

  defp urlset(urls), do: "<urlset>#{Enum.map_join(urls, &"<url><loc>#{&1}</loc></url>")}</urlset>"

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

  defp shared_row_counts do
    Enum.map([Phrase, Metrics, SerpSnapshot], &Repo.aggregate(&1, :count))
  end

  defp google_not_configured do
    stub(Dirmoon.PageSpeedMock, :check, fn _request -> {:error, :page_speed_not_configured} end)
    stub(Dirmoon.DataForSEOMock, :indexed_page_count, fn _request -> {:error, :data_for_seo_not_configured} end)
    stub(Dirmoon.DataForSEOMock, :business_profile, fn _request -> {:error, :data_for_seo_not_configured} end)
    stub(Dirmoon.DataForSEOMock, :linking_sites, fn _request -> {:error, :data_for_seo_not_configured} end)
  end
end
