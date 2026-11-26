defmodule Dirmoon.SiteScans.Findings.Findable do
  @moduledoc """
  Findings for the question "can Google find the site?" (`:findable`):

    * `:https`: no address answers over https (problem), else good
    * `:www_and_bare`: the bare and the `www.` host both answer without one
      sending to the other (warning; figures `addresses`), else good
    * `:robots_txt`: robots.txt blocks the whole site (problem) or could not
      be read (warning), else good; figures `present`, `status`
    * `:noindex`: readable pages asking Google not to list them (warning, a
      problem when the home page is one of them), else good
    * `:sitemap`: no sitemap (warning), else good; figures `url`,
      `page_count`
    * `:broken_links`: internal links the link check found answering 400 or
      more and Scanned Pages answering 400 or more (401 and 403 excepted:
      those ask for a password) (problem; figures `links`, each
      `%{url:, status:, linked_from:}`), else good once the links were
      checked; figures `links_checked`
    * `:unreadable_pages`: Scanned Pages whose read failed with no answer
      and checked links that gave none (warning: a timeout or a dropped
      connection says nothing sure about the page), else good once any page
      was read
    * `:redirect_chains`: pages reached through 2 or more redirects
      (warning; figures `chains`, each `%{url:, redirects:}`), else good
    * `:password_pages`: pages answering 401 or 403, or holding a password
      field and little text (warning), else good
    * `:blocked_pages`: pages robots.txt keeps Google out of (warning), else
      good
    * `:indexed_pages`: Google's rough count of indexed pages against the
      readable pages the scan found: none indexed (problem), fewer than half
      (warning), else good. When the scan read as many pages as it may
      (`page_limit` in the site), the site may have more pages than it read,
      so a count of at least half can't be judged: not checked with the
      reason `"page_limit_reached"`. Not checked with its `reason` when the
      count wasn't looked up. Figures `indexed_count`, `pages_read`,
      `page_limit_reached`

  Lists in figures hold at most `Dirmoon.SiteScans.Finding.max_pages/0`
  items.
  """

  alias Dirmoon.SiteScans.Finding
  alias Dirmoon.SiteScans.Findings.SitePages

  @question :findable
  @checks [
    https: [:problem, :good],
    www_and_bare: [:warning, :good],
    robots_txt: [:problem, :warning, :good],
    noindex: [:problem, :warning, :good],
    sitemap: [:warning, :good],
    broken_links: [:problem, :good],
    unreadable_pages: [:warning, :good],
    redirect_chains: [:warning, :good],
    password_pages: [:warning, :good],
    blocked_pages: [:warning, :good],
    indexed_pages: [:problem, :warning, :not_checked, :good]
  ]
  @check_levels for {check, levels} <- @checks, level <- levels, do: {check, level}
  @redirect_chain_length 2
  @broken_status 400
  @password_statuses [401, 403]
  @indexed_share_warning 0.5
  @page_limit_reached "page_limit_reached"

  @doc "Every check this rule makes, with each level it can give: `[%{question:, check:, level:}]`."
  def checks, do: for({check, level} <- @check_levels, do: %{question: @question, check: check, level: level})

  @doc "The `:findable` Findings of the site (`Dirmoon.SiteScans.Findings`)."
  def check(%{facts: facts, pages: pages} = site) do
    readable = SitePages.readable(pages)

    List.flatten([
      https(facts),
      www_and_bare(facts),
      robots_txt(facts["robots_txt"]),
      noindex(readable, site.home_page),
      sitemap(facts["sitemap"]),
      broken_links(facts, pages),
      unreadable_pages(facts, pages),
      redirect_chains(pages),
      password_pages(pages),
      blocked_pages(facts["blocked_pages"]),
      indexed_pages(facts["indexed_pages"], %{readable: readable, pages: pages, page_limit: site.page_limit})
    ])
  end

  defp https(%{"https" => false}), do: finding(:https, :problem)
  defp https(%{"https" => true}), do: finding(:https, :good)
  defp https(_facts), do: []

  defp www_and_bare(%{"www_and_bare_both_answer" => true} = facts) do
    addresses =
      facts["addresses"]
      |> maps()
      |> Enum.filter(&(&1["status"] == 200 and is_binary(&1["url"])))
      |> Enum.map(& &1["url"])

    finding(:www_and_bare, :warning, %{figures: %{addresses: addresses}})
  end

  defp www_and_bare(%{"www_and_bare_both_answer" => false}), do: finding(:www_and_bare, :good)
  defp www_and_bare(_facts), do: []

  defp robots_txt(%{} = robots_txt) do
    level =
      cond do
        robots_txt["blocks_site"] == true -> :problem
        robots_txt["unreadable"] == true -> :warning
        true -> :good
      end

    finding(:robots_txt, level, %{figures: %{present: robots_txt["present"] == true, status: robots_txt["status"]}})
  end

  defp robots_txt(_missing), do: []

  defp noindex([], _home_page), do: []

  defp noindex(readable, home_page) do
    case Enum.filter(readable, &(&1.facts["noindex"] == true)) do
      [] ->
        finding(:noindex, :good)

      noindex_pages ->
        level = if Enum.any?(noindex_pages, &SitePages.home_page?(&1, home_page)), do: :problem, else: :warning
        finding(:noindex, level, %{pages: Enum.map(noindex_pages, & &1.url)})
    end
  end

  defp sitemap(%{"found" => found} = sitemap) do
    finding(:sitemap, if(found == true, do: :good, else: :warning), %{
      figures: %{url: sitemap["url"], page_count: sitemap["page_count"]}
    })
  end

  defp sitemap(_missing), do: []

  defp broken_links(facts, pages) do
    stored_links = facts["broken_links"] |> checked_links() |> Enum.filter(&is_integer(&1.status))

    broken_pages =
      pages
      |> Enum.filter(&broken_page?/1)
      |> Enum.map(&%{url: &1.url, status: &1.http_status, linked_from: []})

    links = broken_pages ++ stored_links
    figures = %{links: Enum.take(links, Finding.max_pages()), links_checked: facts["links_checked"]}

    cond do
      links != [] -> finding(:broken_links, :problem, %{pages: Enum.map(links, & &1.url), figures: figures})
      is_list(facts["broken_links"]) -> finding(:broken_links, :good, %{figures: figures})
      true -> []
    end
  end

  defp broken_page?(%{http_status: status}) when is_integer(status),
    do: status >= @broken_status and status not in @password_statuses

  defp broken_page?(_unanswered), do: false

  defp unreadable_pages(facts, pages) do
    unanswered_links = facts["broken_links"] |> checked_links() |> Enum.reject(&is_integer(&1.status))
    unanswered_pages = pages |> Enum.filter(&unanswered_page?/1) |> Enum.map(&%{url: &1.url, linked_from: []})
    unreadable = unanswered_pages ++ unanswered_links

    cond do
      unreadable != [] ->
        finding(:unreadable_pages, :warning, %{
          pages: Enum.map(unreadable, & &1.url),
          figures: %{links: unreadable |> Enum.take(Finding.max_pages()) |> Enum.map(&Map.take(&1, [:url, :linked_from]))}
        })

      pages != [] ->
        finding(:unreadable_pages, :good)

      true ->
        []
    end
  end

  defp unanswered_page?(%{http_status: nil, facts: facts}), do: Map.has_key?(facts, "read_error")
  defp unanswered_page?(_answered), do: false

  defp checked_links(links) do
    links
    |> maps()
    |> Enum.filter(&is_binary(&1["url"]))
    |> Enum.map(&%{url: &1["url"], status: &1["status"], linked_from: strings(&1["linked_from"])})
  end

  defp redirect_chains([]), do: []

  defp redirect_chains(pages) do
    case Enum.filter(pages, &(length(List.wrap(&1.facts["redirects"])) >= @redirect_chain_length)) do
      [] ->
        finding(:redirect_chains, :good)

      chained ->
        chains = Enum.map(chained, &%{url: &1.url, redirects: &1.facts["redirects"]})

        finding(:redirect_chains, :warning, %{
          pages: Enum.map(chained, & &1.url),
          figures: %{chains: Enum.take(chains, Finding.max_pages())}
        })
    end
  end

  defp password_pages([]), do: []

  defp password_pages(pages) do
    case Enum.filter(pages, &asks_for_password?/1) do
      [] -> finding(:password_pages, :good)
      locked -> finding(:password_pages, :warning, %{pages: Enum.map(locked, & &1.url)})
    end
  end

  defp asks_for_password?(%{http_status: status}) when status in @password_statuses, do: true

  defp asks_for_password?(page) do
    page.facts["password_field"] == true and SitePages.little_text?(page)
  end

  defp blocked_pages(blocked) when is_list(blocked) do
    case strings(blocked) do
      [] -> finding(:blocked_pages, :good)
      blocked -> finding(:blocked_pages, :warning, %{pages: blocked})
    end
  end

  defp blocked_pages(_missing), do: []

  defp indexed_pages(%{"checked" => true, "count" => count}, %{readable: readable, pages: pages, page_limit: page_limit})
       when is_integer(count) do
    pages_read = length(readable)
    page_limit_reached = length(pages) >= page_limit
    figures = %{indexed_count: count, pages_read: pages_read, page_limit_reached: page_limit_reached}

    cond do
      count == 0 ->
        finding(:indexed_pages, :problem, %{figures: figures})

      count < pages_read * @indexed_share_warning ->
        finding(:indexed_pages, :warning, %{figures: figures})

      page_limit_reached ->
        finding(:indexed_pages, :not_checked, %{figures: Map.put(figures, :reason, @page_limit_reached)})

      true ->
        finding(:indexed_pages, :good, %{figures: figures})
    end
  end

  defp indexed_pages(%{"checked" => false} = indexed_pages, _pages),
    do: finding(:indexed_pages, :not_checked, %{figures: %{reason: indexed_pages["reason"]}})

  defp indexed_pages(_missing, _pages), do: []

  defp maps(list) when is_list(list), do: Enum.filter(list, &is_map/1)
  defp maps(_not_a_list), do: []

  defp strings(list) when is_list(list), do: Enum.filter(list, &is_binary/1)
  defp strings(_not_a_list), do: []

  defp finding(check, level, attributes \\ %{}) when {check, level} in @check_levels,
    do: Finding.new(Map.merge(attributes, %{question: @question, check: check, level: level}))
end
