defmodule Dirmoon.SiteScans.Findings.NicheCoverage do
  @moduledoc """
  Findings for the question "does the site answer what people search
  for?" (`:niche_coverage`), from the matching of the Scanned Pages to the
  run's Niches (the scan's `"matching"` fact and each page's `cluster_id`)
  and the run's Current Positions.

  Pages whose `canonical` names another address are variants, not pages
  (`SitePages.own_pages/1`), and are left out of every page list here.

  Until the matching is done there is one `:niche_matching` Finding, not
  checked, with its `reason`: `"not_ready"` while it hasn't run, else the
  stored one (`"not_in_demo_data"`, `"not_configured"`, `"failed"`). Once
  done:

    * `:niches_without_page`: Niches Worth Going After (not rejected) that
      no readable page is matched to (problem; figures `niches`, each
      `%{id:, name:, volume:}`, and `niche_count`)
    * `:niches_with_page`: those that have one (good; figures `niches`, each
      `%{id:, name:, volume:, pages:}`, and `niche_count`)
    * `:several_pages_for_one_niche`: Niches two or more pages are matched
      to (warning; figures `niches`, each `%{id:, name:, pages:}`), else
      good when any page is matched
    * `:pages_answering_no_phrase`: pages Google may list
      (`SitePages.with_content/1`) other than the home page, matched to no
      Niche and the ranking address of no Phrase (compared with
      `SitePages.same_address?/2`) (warning), else good

  Whatever the matching, `:close_to_first_page` lists the kept Phrases with
  a Current Position from 11 to 20 (`@close_to_first_page`: Google's second
  page, a range of its own, apart from the Quick Win range of
  `Dirmoon.Phrases.quick_win_range/0`), best first (warning, as good news
  to act on; figures `phrases`, each `%{phrase:, position:, url:}`, and
  `phrase_count`).

  Lists in figures hold at most `Dirmoon.SiteScans.Finding.max_pages/0`
  items.
  """

  alias Dirmoon.Niches.Niche
  alias Dirmoon.Niches.Scoring
  alias Dirmoon.SiteScans.Finding
  alias Dirmoon.SiteScans.Findings.SitePages

  @question :niche_coverage
  @checks [
    niche_matching: [:not_checked],
    niches_without_page: [:problem],
    niches_with_page: [:good],
    several_pages_for_one_niche: [:warning, :good],
    pages_answering_no_phrase: [:warning, :good],
    close_to_first_page: [:warning]
  ]
  @check_levels for {check, levels} <- @checks, level <- levels, do: {check, level}
  @close_to_first_page 11..20
  @not_ready "not_ready"

  @doc "Every check this rule makes, with each level it can give: `[%{question:, check:, level:}]`."
  def checks, do: for({check, level} <- @check_levels, do: %{question: @question, check: check, level: level})

  @doc "The `:niche_coverage` Findings of the site (`Dirmoon.SiteScans.Findings`)."
  def check(%{facts: facts} = site) do
    List.flatten([matched(facts["matching"], site), close_to_first_page(site.phrases)])
  end

  defp matched(%{"done" => true}, %{pages: pages, niches: niches, phrases: phrases, home_page: home_page}) do
    own_pages = SitePages.own_pages(pages)
    pages_by_niche = own_pages |> Enum.filter(& &1.cluster_id) |> Enum.group_by(& &1.cluster_id, & &1.url)

    [
      worth_going_after(niches, pages_by_niche),
      several_pages_for_one_niche(niches, pages_by_niche),
      pages_answering_no_phrase(SitePages.with_content(pages), %{phrases: phrases, home_page: home_page})
    ]
  end

  defp matched(%{"reason" => reason}, _site), do: not_checked(reason)
  defp matched(_not_done, _site), do: not_checked(@not_ready)

  defp not_checked(reason), do: finding(:niche_matching, :not_checked, %{figures: %{reason: reason}})

  defp worth_going_after(summaries, pages_by_niche) do
    {with_page, without_page} =
      summaries
      |> Enum.filter(&(Niche.choosable?(&1.niche) and Scoring.worth?(&1.niche.score)))
      |> Enum.split_with(&Map.has_key?(pages_by_niche, &1.niche.id))

    [
      niches_without_page(without_page),
      niches_with_page(with_page, pages_by_niche)
    ]
  end

  defp niches_without_page([]), do: []

  defp niches_without_page(summaries),
    do:
      finding(:niches_without_page, :problem, %{
        figures: %{
          niches: summaries |> Enum.take(Finding.max_pages()) |> Enum.map(&niche_figures/1),
          niche_count: length(summaries)
        }
      })

  defp niches_with_page([], _pages_by_niche), do: []

  defp niches_with_page(summaries, pages_by_niche) do
    niches = Enum.map(summaries, &Map.put(niche_figures(&1), :pages, Map.fetch!(pages_by_niche, &1.niche.id)))

    finding(:niches_with_page, :good, %{
      pages: Enum.flat_map(niches, & &1.pages),
      figures: %{niches: Enum.take(niches, Finding.max_pages()), niche_count: length(niches)}
    })
  end

  defp niche_figures(%{niche: niche, volume: volume}), do: %{id: niche.id, name: niche.name, volume: volume}

  defp several_pages_for_one_niche(_summaries, pages_by_niche) when map_size(pages_by_niche) == 0, do: []

  defp several_pages_for_one_niche(summaries, pages_by_niche) do
    niches =
      summaries
      |> Enum.filter(&match?([_, _ | _], Map.get(pages_by_niche, &1.niche.id, [])))
      |> Enum.map(&%{id: &1.niche.id, name: &1.niche.name, pages: Map.fetch!(pages_by_niche, &1.niche.id)})

    case niches do
      [] ->
        finding(:several_pages_for_one_niche, :good)

      niches ->
        finding(:several_pages_for_one_niche, :warning, %{
          pages: Enum.flat_map(niches, & &1.pages),
          figures: %{niches: Enum.take(niches, Finding.max_pages())}
        })
    end
  end

  defp pages_answering_no_phrase(listable, %{phrases: phrases, home_page: home_page}) do
    ranking_addresses = phrases |> Enum.map(& &1.current_position_url) |> Enum.filter(&is_binary/1)

    case Enum.reject(listable, &SitePages.home_page?(&1, home_page)) do
      [] ->
        []

      pages ->
        pages
        |> Enum.filter(&(is_nil(&1.cluster_id) and not ranks?(&1, ranking_addresses)))
        |> then(fn
          [] -> finding(:pages_answering_no_phrase, :good)
          unanswered -> finding(:pages_answering_no_phrase, :warning, %{pages: Enum.map(unanswered, & &1.url)})
        end)
    end
  end

  defp ranks?(page, ranking_addresses) do
    Enum.any?(ranking_addresses, fn address ->
      SitePages.same_address?(address, page.url) or SitePages.same_address?(address, page.facts["final_url"])
    end)
  end

  defp close_to_first_page(phrases) do
    close =
      phrases
      |> Enum.filter(&(&1.status == :kept and close_to_first_page?(&1.current_position)))
      |> Enum.sort_by(& &1.phrase.phrase)
      |> Enum.sort_by(& &1.current_position, Decimal)
      |> Enum.map(&%{phrase: &1.phrase.phrase, position: &1.current_position, url: &1.current_position_url})

    case close do
      [] ->
        []

      close ->
        finding(:close_to_first_page, :warning, %{
          pages: close |> Enum.map(& &1.url) |> Enum.filter(&is_binary/1),
          figures: %{phrases: Enum.take(close, Finding.max_pages()), phrase_count: length(close)}
        })
    end
  end

  defp close_to_first_page?(%Decimal{} = position) do
    Decimal.compare(position, @close_to_first_page.first) != :lt and
      Decimal.compare(position, @close_to_first_page.last) != :gt
  end

  defp close_to_first_page?(nil), do: false

  defp finding(check, level, attributes \\ %{}) when {check, level} in @check_levels,
    do: Finding.new(Map.merge(attributes, %{question: @question, check: check, level: level}))
end
