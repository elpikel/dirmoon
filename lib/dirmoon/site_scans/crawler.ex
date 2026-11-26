defmodule Dirmoon.SiteScans.Crawler do
  @moduledoc """
  Reads an Existing Site for its Site Scan and stores what it finds as
  facts, never as judgements: the Findings are worked out from them later.
  Every address goes through the web page seam (`Dirmoon.WebPage.fetch/1`),
  which reads only public addresses, so a link or redirect to a private or
  local address is never requested. Nothing goes to the shared market
  tables. Reading the site's own pages costs nothing and is not recorded;
  what others say about the site (step 6 below: the speed check at no
  cost, the paid indexed page count, Business Profile and linking sites)
  goes through the run's ledger.

  The crawl, in order:

    1. **Address variants.** `https://` and `http://`, each on the bare and
       the `www.` host. The home page is where the first variant answering
       200 ends up; when none does, the crawl is an error.
    2. **robots.txt** of the home page's origin (`Dirmoon.SiteScans.Robots`),
       for every crawler: a 4xx means no file and everything is allowed; a
       5xx or no answer is noted as unreadable and everything is allowed.
    3. **Sitemap.** The sitemaps robots.txt names, else `/sitemap.xml`; a
       sitemap index's nested sitemaps are read too, at most five sitemap
       documents in all (`Dirmoon.SiteScans.Sitemap`).
    4. **Walk.** Breadth-first from the home page through the internal
       links of the pages read (only from pages answering 2xx), then the
       sitemap's pages, four at a time, up to `Dirmoon.SiteScans.page_limit/0`
       Scanned Pages. Only addresses on the site's host (the home page's
       final host, a leading `www.` ignored) are read; addresses robots.txt
       disallows are noted as blocked and not requested. A page whose read
       ends on another host is stored without Page Facts and its links are
       not followed. At most twice the page limit of linked addresses are
       ever queued; links found beyond that are not tracked.
    5. **Link check.** Internal links found but not read, the first 200 of
       them: up to 100 robots.txt allows are requested and the broken ones
       noted.
    6. **What others say** (`Dirmoon.SiteScans.OutsideFacts`): the home
       page's phone speed, the indexed page count, the Google Business
       Profile and how many other sites link to the site, through the run's
       ledger. None of them can fail the scan.

  robots.txt is applied to an address only when it is about to be read or
  link-checked, and once per address: the verdict is kept for the whole
  crawl. So a crawl makes at most 1 + 2 × 50 (linked) + 2 × 50 (sitemap) +
  200 (link check) = 401 checks at the default page limit, however many
  links its pages hold.
  The pages of a batch are read in tasks linked to the crawl's process, so
  killing the scan ends them (and, through `Dirmoon.WebPage.HTTP`'s
  watcher, their reads); a read that crashes is stored as unreadable and
  the crawl carries on.

  Addresses are normalised so one page is read once: the scheme and host
  lower-cased, the default port and the fragment dropped, an empty path
  made `/`; the query and a trailing slash are kept as they are, since they
  may make another page. An address a read was redirected to counts as
  read.

  Each page is stored as soon as its batch is read
  (`Dirmoon.SiteScans.record_pages/2`), so a resumed crawl never requests a
  stored page again and goes on from the stored pages' links; the site
  facts below, once stored, are reused too, except robots.txt, which is
  read again for its rules.

  ## Facts on the scan (`site_scan.facts`)

    * `"home_page"`: the address the crawl starts from (string)
    * `"addresses"`: one map per variant, in the order above:
      `%{"url" => string, "status" => integer | nil, "final_url" => string | nil,
      "redirects" => [string], "error" => string | nil}`
    * `"https"`: whether a variant answers 200 over https (boolean)
    * `"www_and_bare_both_answer"`: whether the bare and the `www.` host
      both answer 200 over the same scheme without one redirecting to the
      other's host (boolean)
    * `"robots_txt"`: `%{"present" => boolean, "status" => integer | nil,
      "unreadable" => boolean, "blocks_site" => boolean,
      "sitemaps" => [up to 10 strings]}`. The rules themselves (up to 500,
      `Dirmoon.SiteScans.Robots`) are not stored: every try of the crawl
      reads robots.txt again and keeps them in memory
    * `"sitemap"`: `%{"found" => boolean, "url" => string | nil,
      "page_count" => integer, "pages" => [string]}`; `"url"` is the first
      sitemap that listed anything, `"page_count"` the distinct pages on the
      site's host it lists (other hosts left out), and `"pages"` the first
      of them, normalised: twice the page limit, as many as a crawl (or a
      resumed one, which reads them from here) can take after the linked
      pages, and no more than fit in 64 KiB together
    * `"blocked_pages"`: up to 50 internal addresses robots.txt kept the
      crawl from reading or link-checking, as it met them, that fit in
      32 KiB together ([string])
    * `"links_checked"`: how many unread internal links were requested
      (integer)
    * `"broken_links"`: those that answered 400 or more, or could not be
      read: `[%{"url" => string, "status" => integer | nil,
      "linked_from" => [up to 3 Scanned Page addresses]}]`, at most 100,
      and no more than fit in 64 KiB of addresses together

  What others say, each either checked or
  `%{"checked" => false, "reason" => string}` (the reasons listed per key):

    * `"speed"`: Google PageSpeed Insights for the home page on a phone,
      `%{"checked" => true}` merged with the result `Dirmoon.PageSpeed`
      documents: `"performance_score"` (0–100 or nil),
      `"largest_contentful_paint_ms"`, `"total_blocking_time_ms"`,
      `"cumulative_layout_shift"` (Google's test load, each nil when
      missing), `"lighthouse_version"`, `"field"` (real visitors' figures,
      a map of up to `"largest_contentful_paint"`,
      `"interaction_to_next_paint"` and `"cumulative_layout_shift"` to
      `%{"percentile" => number, "category" => string | nil,
      "scope" => "page" | "origin"}`) and `"phone_checks"`
      (`[%{"id" => string, "passed" => boolean | nil}]`). Reasons:
      `"not_configured"` (no key, or the key refused), `"quota"`,
      `"page_unreachable"` (Google could not load the page), `"failed"`
    * `"indexed_pages"`: `%{"checked" => true, "count" => integer}`,
      Google's rough count of the domain's pages (a `site:` search in the
      run's country and language). Reasons: `"not_configured"`,
      `"not_in_demo_data"`, `"failed"`
    * `"business_profile"`: the Google Business Profile for the business
      name the Scanned Pages' structured data gives (home page first), in
      the run's city, else its country: `%{"checked" => true,
      "name" => string (the name looked up), "found" => boolean,
      "links_to_site" => boolean (the profile's website is on the home
      page's host, `www.` ignored), "title" | "phone" | "address" =>
      string | nil (Google's, at most 300 bytes each),
      "rating" => number | nil, "votes" => integer | nil,
      "claimed" => boolean | nil}`; when nothing is found, `"found"` and
      `"links_to_site"` are false and the rest nil. Reasons:
      `"no_business_name"` (no lookup made), `"unavailable"` (DataForSEO
      refused the task, e.g. for the location), `"not_configured"`,
      `"not_in_demo_data"`, `"failed"`
    * `"linking_sites"`: `%{"checked" => true, "count" => integer | nil}`,
      how many other sites DataForSEO's link index knows to link to the
      run's domain; `nil` when it has no data for the domain. Reasons:
      `"unavailable"` (DataForSEO refused the request, e.g. no access to its
      link data), `"not_configured"`, `"not_in_demo_data"`, `"failed"`

  The scan is loaded again on every update a subscriber hears of, so its
  facts are kept small: under 300 KB of text as jsonb stores it, whatever
  the site. Worst case: the four address variants with up to five
  redirects each, every address 2,048 bytes, under 60 KB; robots.txt's
  sitemaps 20 KB; the sitemap 66 KB; the blocked pages 32 KB; the broken
  links 64 KiB of addresses plus their statuses; the speed, indexed pages,
  Business Profile, linking sites and matching facts a few KB together.

  ## Facts on a Scanned Page (`scanned_page.facts`)

  For an HTML or XHTML answer, the Page Facts
  (`Dirmoon.WebPage.PageFacts.from_html/2`, read at the final address);
  for any answer, `"final_url"` (string), `"redirects"` (the addresses it
  was sent through before the final one, [string]) and `"content_type"`
  (string or nil). A page whose read ended on another host has
  `"off_site" => true` instead of Page Facts. A page that could not be read
  has `http_status` nil and only `"read_error"` (string). The content type
  is kept to 255 bytes, so a Scanned Page's facts hold under 175 KB of
  text as jsonb stores it: the Page Facts under 160 KB, plus the final
  address and up to five redirect addresses of at most 2,048 bytes each.

  Every stored address passed `Dirmoon.WebPage.WebAddress` (at most 2,048
  bytes) on its way in: links and the canonical through the Page Facts,
  sitemap addresses through `Dirmoon.SiteScans.Sitemap`, robots.txt's
  sitemap lines through `Dirmoon.SiteScans.Robots`, and the final and
  redirect addresses through the web page seam.
  """

  alias Dirmoon.JsonSafe
  alias Dirmoon.Research.Run
  alias Dirmoon.SiteScans
  alias Dirmoon.SiteScans.OutsideFacts
  alias Dirmoon.SiteScans.Robots
  alias Dirmoon.SiteScans.Sitemap
  alias Dirmoon.SiteScans.SiteScan
  alias Dirmoon.WebPage
  alias Dirmoon.WebPage.HostName
  alias Dirmoon.WebPage.PageFacts

  @pages_at_a_time 4
  @max_sitemap_documents 5
  @max_blocked_pages 50
  @max_checked_links 100
  @max_link_check_candidates 200
  @max_linked_from 3
  @max_stored_robots_sitemaps 10
  @max_sitemap_pages_bytes 65_536
  @max_blocked_pages_bytes 32_768
  @max_broken_links_bytes 65_536
  @max_content_type_bytes 255
  @sitemap_frontier_factor 2
  @link_frontier_factor 2
  @html_content_types ["text/html", "application/xhtml+xml"]
  @read_crashed "the page could not be read"
  @cannot_open "The site could not be opened: none of its addresses answered with a page"

  @doc """
  Crawls the site of a scan loaded by `Dirmoon.SiteScans.get_scanning/1`
  (with its run and Scanned Pages).

  Returns `{:ok, site_scan}` with the facts stored, or `{:error, reason}`
  with a readable reason when no address of the site answers with a page.
  """
  def crawl(%SiteScan{run: %Run{domain: domain} = run, scanned_pages: stored_pages} = site_scan)
      when is_binary(domain) and is_list(stored_pages) do
    with {:ok, %{site_scan: site_scan, prefetched: prefetched}} <- address_facts(site_scan, Run.ascii_domain(run)) do
      %{site_scan: site_scan, rules: rules} = robots_facts(site_scan)

      site_scan
      |> sitemap_facts()
      |> start_walk(%{stored_pages: stored_pages, prefetched: prefetched, rules: rules})
      |> walk()
      |> check_links()
      |> then(&{:ok, OutsideFacts.gather(&1.site_scan, &1.pages)})
    end
  end

  defp address_facts(%SiteScan{facts: %{"home_page" => _home_page}} = site_scan, _domain),
    do: {:ok, %{site_scan: site_scan, prefetched: %{}}}

  defp address_facts(site_scan, domain) do
    answers = Enum.map(variants(domain), &{&1, WebPage.fetch(&1)})

    case Enum.find(answers, fn {_url, answer} -> answers_page?(answer) end) do
      {_url, {:ok, %{url: final_url} = home}} ->
        home_page = normalise(final_url)

        facts = %{
          "home_page" => home_page,
          "addresses" => Enum.map(answers, &address_fact/1),
          "https" => Enum.any?(answers, &answers_over_https?/1),
          "www_and_bare_both_answer" => www_and_bare_both_answer?(answers)
        }

        {:ok, %{site_scan: SiteScans.put_facts(site_scan, facts), prefetched: %{home_page => {:ok, home}}}}

      nil ->
        {:error, @cannot_open}
    end
  end

  defp variants(domain) do
    for scheme <- ["https", "http"], host <- [domain, "www." <> domain], do: "#{scheme}://#{host}/"
  end

  defp answers_page?({:ok, %{status: 200}}), do: true
  defp answers_page?(_other), do: false

  defp address_fact({url, {:ok, answer}}),
    do: %{
      "url" => url,
      "status" => answer.status,
      "final_url" => answer.url,
      "redirects" => answer.redirects,
      "error" => nil
    }

  defp address_fact({url, {:error, reason}}),
    do: %{"url" => url, "status" => nil, "final_url" => nil, "redirects" => [], "error" => reason}

  defp answers_over_https?({_url, {:ok, %{status: 200, url: "https://" <> _rest}}}), do: true
  defp answers_over_https?(_other), do: false

  defp www_and_bare_both_answer?([https_bare, https_www, http_bare, http_www]) do
    both_answer_apart?(https_bare, https_www) or both_answer_apart?(http_bare, http_www)
  end

  defp both_answer_apart?({_bare, {:ok, %{status: 200, url: bare_final}}}, {_www, {:ok, %{status: 200, url: www_final}}}),
    do: URI.parse(bare_final).host != URI.parse(www_final).host

  defp both_answer_apart?(_bare, _www), do: false

  defp robots_facts(%SiteScan{facts: %{"home_page" => home_page}} = site_scan) do
    %{fact: fact, rules: rules} =
      home_page
      |> origin_address("/robots.txt")
      |> WebPage.fetch()
      |> robots_txt()

    robots_fact = Map.put(fact, "blocks_site", not Robots.allowed?(rules, "/"))
    %{site_scan: SiteScans.put_facts(site_scan, %{"robots_txt" => robots_fact}), rules: rules}
  end

  defp robots_txt({:ok, %{status: status, body: body}}) when status in 200..299 do
    %{rules: rules, sitemaps: sitemaps} = Robots.parse(body)

    %{
      fact: %{
        "present" => true,
        "status" => status,
        "unreadable" => false,
        "sitemaps" => Enum.take(sitemaps, @max_stored_robots_sitemaps)
      },
      rules: rules
    }
  end

  defp robots_txt({:ok, %{status: status}}) when status in 400..499,
    do: no_robots_txt(%{status: status, unreadable: false})

  defp robots_txt({:ok, %{status: status}}), do: no_robots_txt(%{status: status, unreadable: true})
  defp robots_txt({:error, _reason}), do: no_robots_txt(%{status: nil, unreadable: true})

  defp no_robots_txt(%{status: status, unreadable: unreadable}),
    do: %{fact: %{"present" => false, "status" => status, "unreadable" => unreadable, "sitemaps" => []}, rules: []}

  defp sitemap_facts(%SiteScan{facts: %{"sitemap" => _sitemap}} = site_scan), do: site_scan

  defp sitemap_facts(%SiteScan{facts: %{"home_page" => home_page, "robots_txt" => robots_txt}} = site_scan) do
    sitemaps =
      case robots_txt["sitemaps"] do
        [] -> [origin_address(home_page, "/sitemap.xml")]
        named -> named
      end

    %{url: url, pages: pages} = read_sitemaps(sitemaps, %{read: 0, url: nil, pages: []})
    site_host = site_host(home_page)

    site_pages =
      pages
      |> Enum.map(&normalise/1)
      |> Enum.filter(&same_site?(&1, site_host))
      |> Enum.uniq()

    SiteScans.put_facts(site_scan, %{
      "sitemap" => %{
        "found" => url != nil,
        "url" => url,
        "page_count" => length(site_pages),
        "pages" =>
          site_pages
          |> Enum.take(SiteScans.page_limit() * @sitemap_frontier_factor)
          |> within_bytes(%{max_bytes: @max_sitemap_pages_bytes, size: &byte_size/1})
      }
    })
  end

  defp read_sitemaps([], reading), do: reading
  defp read_sitemaps(_sitemaps, %{read: @max_sitemap_documents} = reading), do: reading

  defp read_sitemaps([sitemap | rest], reading) do
    reading = %{reading | read: reading.read + 1}

    case WebPage.fetch(sitemap) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        %{page_urls: page_urls, sitemap_urls: sitemap_urls} = Sitemap.urls(body)
        listed? = page_urls != [] or sitemap_urls != []
        url = reading.url || if(listed?, do: sitemap)
        read_sitemaps(rest ++ sitemap_urls, %{reading | url: url, pages: reading.pages ++ page_urls})

      _not_a_sitemap ->
        read_sitemaps(rest, reading)
    end
  end

  defp start_walk(%SiteScan{facts: facts} = site_scan, %{stored_pages: stored_pages, prefetched: prefetched, rules: rules}) do
    blocked = Map.get(facts, "blocked_pages", [])
    read = stored_pages |> Enum.flat_map(&[&1.url, &1.facts["final_url"]]) |> normalised_set()

    walk = %{
      site_scan: site_scan,
      site_host: site_host(facts["home_page"]),
      rules: rules,
      robots_verdicts: %{},
      seen: MapSet.union(read, MapSet.new(blocked)),
      link_queue: [],
      links_queued: 0,
      sitemap_queue: facts["sitemap"]["pages"],
      blocked: Enum.reverse(blocked),
      pages: stored_pages,
      next_position: next_position(stored_pages),
      prefetched: prefetched
    }

    walk
    |> enqueue_links([facts["home_page"]])
    |> then(&Enum.reduce(stored_pages, &1, fn page, walk -> enqueue_links(walk, followable_links(page)) end))
  end

  defp walk(%{site_scan: site_scan} = walk) do
    case next_addresses(walk, max(SiteScans.page_limit() - site_scan.pages_read, 0)) do
      {[], walk} ->
        walk

      {addresses, walk} ->
        pages = read_pages(addresses, walk)
        site_scan = SiteScans.record_pages(site_scan, pages)

        walk = %{
          walk
          | site_scan: site_scan,
            pages: walk.pages ++ pages,
            next_position: walk.next_position + length(pages)
        }

        pages
        |> Enum.reduce(walk, fn page, walk ->
          walk
          |> mark_seen(page.facts["final_url"])
          |> enqueue_links(followable_links(page))
        end)
        |> walk()
    end
  end

  defp next_addresses(%{link_queue: []} = walk, room),
    do: take_addresses(walk, %{from: :sitemap, taken: [], wanted: min(room, @pages_at_a_time)})

  defp next_addresses(walk, room),
    do: take_addresses(walk, %{from: :links, taken: [], wanted: min(room, @pages_at_a_time)})

  defp take_addresses(walk, %{taken: taken, wanted: 0}), do: {Enum.reverse(taken), walk}

  defp take_addresses(%{link_queue: [address | rest]} = walk, %{from: :links} = taking),
    do: take_if_allowed(%{walk | link_queue: rest}, address, taking)

  defp take_addresses(%{sitemap_queue: [url | rest]} = walk, %{from: :sitemap} = taking) do
    address = normalise(url)
    walk = %{walk | sitemap_queue: rest}

    if new_on_site?(walk, address),
      do: take_if_allowed(%{walk | seen: MapSet.put(walk.seen, address)}, address, taking),
      else: take_addresses(walk, taking)
  end

  defp take_addresses(walk, %{taken: taken}), do: {Enum.reverse(taken), walk}

  defp take_if_allowed(walk, address, %{taken: taken, wanted: wanted} = taking) do
    case robots_verdict(walk, address) do
      {true, walk} -> take_addresses(walk, %{taking | taken: [address | taken], wanted: wanted - 1})
      {false, walk} -> take_addresses(walk, taking)
    end
  end

  defp enqueue_links(walk, urls) do
    {queued, walk} = Enum.reduce_while(urls, {[], walk}, &queue_link/2)
    %{walk | link_queue: walk.link_queue ++ Enum.reverse(queued)}
  end

  defp queue_link(url, {queued, walk}) do
    address = normalise(url)

    cond do
      walk.links_queued >= link_frontier_limit() ->
        {:halt, {queued, walk}}

      new_on_site?(walk, address) ->
        {:cont, {[address | queued], %{walk | seen: MapSet.put(walk.seen, address), links_queued: walk.links_queued + 1}}}

      true ->
        {:cont, {queued, walk}}
    end
  end

  defp new_on_site?(walk, address), do: same_site?(address, walk.site_host) and not MapSet.member?(walk.seen, address)

  defp link_frontier_limit, do: SiteScans.page_limit() * @link_frontier_factor

  defp robots_verdict(%{rules: rules, robots_verdicts: robots_verdicts} = walk, address) do
    case robots_verdicts do
      %{^address => allowed?} ->
        {allowed?, walk}

      %{} ->
        allowed? = Robots.allowed?(rules, robots_path(address))
        walk = %{walk | robots_verdicts: Map.put(robots_verdicts, address, allowed?)}
        {allowed?, if(allowed?, do: walk, else: block(walk, address))}
    end
  end

  defp block(%{blocked: blocked} = walk, address) do
    if length(blocked) < @max_blocked_pages, do: %{walk | blocked: [address | blocked]}, else: walk
  end

  defp mark_seen(walk, url), do: %{walk | seen: MapSet.union(walk.seen, normalised_set([url]))}

  defp read_pages(addresses, %{prefetched: prefetched, next_position: next_position, site_host: site_host}) do
    addresses
    |> fetch_all(&Map.get_lazy(prefetched, &1, fn -> WebPage.fetch(&1) end))
    |> Enum.zip(next_position..(next_position + length(addresses) - 1))
    |> Enum.map(fn {{address, answer}, position} ->
      address |> scanned_page(%{answer: answer, site_host: site_host}) |> Map.put(:position, position)
    end)
  end

  defp fetch_all(addresses, fetch) do
    addresses
    |> Task.async_stream(&read_safely(fetch, &1), max_concurrency: @pages_at_a_time, timeout: :infinity)
    |> Enum.zip_with(addresses, fn {:ok, answer}, address -> {address, answer} end)
  end

  defp read_safely(fetch, address) do
    fetch.(address)
  catch
    _kind, _reason -> {:error, @read_crashed}
  end

  defp scanned_page(address, %{answer: {:ok, answer}, site_host: site_host}) do
    %{
      url: address,
      http_status: answer.status,
      facts:
        answer
        |> page_facts(site_host)
        |> Map.merge(%{
          "final_url" => answer.url,
          "redirects" => answer.redirects,
          "content_type" => stored_content_type(answer.content_type)
        })
    }
  end

  defp scanned_page(address, %{answer: {:error, reason}}),
    do: %{url: address, http_status: nil, facts: %{"read_error" => reason}}

  defp stored_content_type(nil), do: nil
  defp stored_content_type(content_type), do: JsonSafe.text(content_type, @max_content_type_bytes)

  defp page_facts(%{url: url} = answer, site_host) do
    if url |> normalise() |> same_site?(site_host), do: site_page_facts(answer), else: %{"off_site" => true}
  end

  defp site_page_facts(%{content_type: content_type, body: body, url: url}) when content_type in @html_content_types,
    do: PageFacts.from_html(body, url)

  defp site_page_facts(_not_html), do: %{}

  defp check_links(%{site_scan: site_scan, pages: pages} = walk) do
    read = pages |> Enum.flat_map(&[&1.url, &1.facts["final_url"]]) |> normalised_set()

    %{order: order, linked_from: linked_from} =
      unread_links(pages, %{links: %{order: [], linked_from: %{}}, site_host: walk.site_host, read: read})

    {checked, walk} = order |> Enum.reverse() |> allowed_links(walk)

    broken_links =
      checked
      |> fetch_all(&WebPage.fetch/1)
      |> Enum.flat_map(fn {address, answer} -> broken_link(address, answer, linked_from) end)

    blocked_pages =
      walk.blocked
      |> Enum.reverse()
      |> within_bytes(%{max_bytes: @max_blocked_pages_bytes, size: &byte_size/1})

    %{
      walk
      | site_scan:
          SiteScans.put_facts(site_scan, %{
            "blocked_pages" => blocked_pages,
            "links_checked" => length(checked),
            "broken_links" =>
              within_bytes(broken_links, %{max_bytes: @max_broken_links_bytes, size: &broken_link_bytes/1})
          })
    }
  end

  defp allowed_links(candidates, walk) do
    {allowed, walk} =
      Enum.reduce_while(candidates, {[], walk}, fn
        _address, {allowed, walk} when length(allowed) == @max_checked_links ->
          {:halt, {allowed, walk}}

        address, {allowed, walk} ->
          case robots_verdict(walk, address) do
            {true, walk} -> {:cont, {[address | allowed], walk}}
            {false, walk} -> {:cont, {allowed, walk}}
          end
      end)

    {Enum.reverse(allowed), walk}
  end

  defp unread_links(pages, %{links: links} = context) do
    Enum.reduce(pages, links, fn page, links ->
      page
      |> followable_links()
      |> Enum.reduce(links, &note_link(&1, &2, Map.put(context, :page_url, page.url)))
    end)
  end

  defp note_link(url, %{linked_from: linked_from} = links, %{site_host: site_host, read: read, page_url: page_url}) do
    address = normalise(url)

    cond do
      not same_site?(address, site_host) or MapSet.member?(read, address) -> links
      Map.has_key?(linked_from, address) -> add_linking_page(links, %{address: address, page_url: page_url})
      map_size(linked_from) >= @max_link_check_candidates -> links
      true -> %{links | order: [address | links.order], linked_from: Map.put(linked_from, address, [page_url])}
    end
  end

  defp add_linking_page(%{linked_from: linked_from} = links, %{address: address, page_url: page_url}) do
    case Map.fetch!(linked_from, address) do
      pages when length(pages) < @max_linked_from ->
        %{links | linked_from: %{linked_from | address => Enum.uniq([page_url | pages])}}

      _enough_pages ->
        links
    end
  end

  defp broken_link(address, {:ok, %{status: status}}, linked_from) when status >= 400,
    do: [%{"url" => address, "status" => status, "linked_from" => linked_from |> Map.fetch!(address) |> Enum.reverse()}]

  defp broken_link(_address, {:ok, _answer}, _linked_from), do: []

  defp broken_link(address, {:error, _reason}, linked_from),
    do: [%{"url" => address, "status" => nil, "linked_from" => linked_from |> Map.fetch!(address) |> Enum.reverse()}]

  defp broken_link_bytes(%{"url" => url, "linked_from" => linked_from}),
    do: byte_size(url) + (linked_from |> Enum.map(&byte_size/1) |> Enum.sum())

  defp within_bytes(items, %{max_bytes: max_bytes, size: size}) do
    items
    |> Enum.reduce_while({[], 0}, fn item, {kept, bytes} ->
      bytes = bytes + size.(item)
      if bytes <= max_bytes, do: {:cont, {[item | kept], bytes}}, else: {:halt, {kept, bytes}}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp followable_links(%{http_status: status, facts: %{"internal_links" => links}}) when status in 200..299, do: links
  defp followable_links(_page), do: []

  defp normalise(url) do
    %URI{host: host, path: path} = uri = URI.parse(url)
    URI.to_string(%{uri | host: HostName.canonical(host), path: blank_path(path), fragment: nil, userinfo: nil})
  end

  defp normalised_set(urls) do
    urls
    |> Enum.filter(&is_binary/1)
    |> MapSet.new(&normalise/1)
  end

  defp blank_path(path) when path in [nil, ""], do: "/"
  defp blank_path(path), do: path

  defp site_host(home_page), do: home_page |> URI.parse() |> Map.fetch!(:host) |> HostName.bare()

  defp same_site?(address, site_host), do: address |> URI.parse() |> Map.fetch!(:host) |> HostName.bare() == site_host

  defp robots_path(address) do
    case URI.parse(address) do
      %URI{path: path, query: nil} -> path
      %URI{path: path, query: query} -> path <> "?" <> query
    end
  end

  defp origin_address(home_page, path), do: home_page |> URI.merge(path) |> URI.to_string()

  defp next_position([]), do: 1
  defp next_position(stored_pages), do: (stored_pages |> Enum.map(& &1.position) |> Enum.max()) + 1
end
