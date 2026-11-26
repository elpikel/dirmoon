defmodule Dirmoon.SiteScans.Findings do
  @moduledoc """
  Works out a Site Scan's Findings from its stored facts (the keys are
  listed in `Dirmoon.SiteScans.Crawler`), the run's Niches and its
  Phrases. Pure: no Repo, no I/O and no sentences; the web layer words
  each Finding by its `check`.

  One rule module per question, each with `check/1`:
  `Dirmoon.SiteScans.Findings.Findable`, `PageContent`, `NicheCoverage`,
  `Visitor` and `Business`. Each takes the site as
  `%{facts:, pages:, home_page:, niches:, phrases:, page_limit:}` and
  answers its Findings; a check whose facts are not stored yet (a scan
  still at work) gives no Finding, and a fact of an unexpected type counts
  as not stored, so the Findings can be built at any time and never raise.
  Each rule lists the checks and levels it can give (`checks/0`), and can
  give no other.
  """

  alias Dirmoon.SiteScans.Finding
  alias Dirmoon.SiteScans.Findings.Business
  alias Dirmoon.SiteScans.Findings.Findable
  alias Dirmoon.SiteScans.Findings.NicheCoverage
  alias Dirmoon.SiteScans.Findings.PageContent
  alias Dirmoon.SiteScans.Findings.Visitor
  alias Dirmoon.SiteScans.SiteScan

  @rules [Findable, PageContent, NicheCoverage, Visitor, Business]

  @doc """
  Every check × level pair the rules can give, in rule order:
  `[%{question:, check:, level:}]`.
  """
  def checks, do: Enum.flat_map(@rules, & &1.checks())

  @doc """
  The Findings of `scan` (with its Scanned Pages), given the run's Niche
  summaries (`Dirmoon.Niches.list_summaries/1`), its Phrases
  (`Dirmoon.Phrases.list_for_run/2`) and the most pages a scan reads
  (`page_limit`), ordered by question (`Finding.questions/0`), then by
  level (`Finding.levels/0`), then in each rule's order.
  """
  def build(%{
        scan: %SiteScan{facts: facts, scanned_pages: pages},
        niches: niches,
        phrases: phrases,
        page_limit: page_limit
      })
      when is_list(pages) and is_list(niches) and is_list(phrases) and is_integer(page_limit) do
    site = %{
      facts: facts,
      pages: pages,
      home_page: facts["home_page"],
      niches: niches,
      phrases: phrases,
      page_limit: page_limit
    }

    @rules
    |> Enum.flat_map(& &1.check(site))
    |> Enum.sort_by(&{index_of(Finding.questions(), &1.question), index_of(Finding.levels(), &1.level)})
  end

  defp index_of(list, item), do: Enum.find_index(list, &(&1 == item))
end
