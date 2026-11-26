defmodule Dirmoon.Phrases.CurrentPositions do
  @moduledoc """
  Step 6: where the Existing Site already shows up on Google for the run's
  Phrases. One source answers, in this order:

    * **Search Console**, when the Account's Connection can read the domain
      and has queries for it: its 90-day average positions alone, nothing
      bought. A property with no queries tells nothing, so it falls through.
    * Otherwise **Google's results**: the keyword API's ranked phrases for the
      domain in the run's country, bought through the run's ledger, plus the
      run's own SERP Snapshots (Step 5) for the Phrases the ranked phrases
      did not give a position. A result counts as the site when its host is
      the run's domain or `www.` and the domain, in either the Unicode or
      the ASCII form of an international name; other subdomains don't.
      When DataForSEO can't give the ranked phrases for the run (it fails
      the task, e.g. for a country Labs doesn't cover, or it answers from
      Demo Data), the Step carries on with the first pages only and keeps
      the reason; a refusal DataForSEO reported is recorded in the ledger
      with its cost, so a retry or resume doesn't ask and pay again.

  Positions are stored per run (`run_keywords`); nothing is written to the
  shared market tables (ADR-0002).
  """

  alias Dirmoon.Competition
  alias Dirmoon.DataForSEO
  alias Dirmoon.Format
  alias Dirmoon.Phrases
  alias Dirmoon.Phrases.Phrase
  alias Dirmoon.Research.Ledger
  alias Dirmoon.Research.Run
  alias Dirmoon.SearchConsole.Positions
  alias Dirmoon.WebPage.HostName

  @search_console "search_console"
  @ranked_phrases "ranked_phrases"
  @first_pages "first_pages"
  @new_idea_result "New idea, no site yet"
  @not_found_result "Your site doesn't show up yet for these searches"
  @not_on_first_pages_result "Your site isn't on Google's first page for these searches; " <>
                               "where it ranks further down couldn't be checked"
  @not_in_demo_data "Demo Data has no ranked phrases"
  @no_search_console_rows "Search Console has no data for this domain"
  @source_names %{
    @search_console => "Search Console",
    @ranked_phrases => "Google's results",
    @first_pages => "Google's first pages only"
  }
  @phrase_forms %{one: "search", other: "searches"}

  @doc """
  Sets the run's Current Positions from the first source that can answer.

  Returns `{:ok, %{result: line, output: output}}`, `{:skip, line}` for a
  New Idea run, or `{:error, reason}` (a Search Console or keyword API
  failure to retry, or `:data_for_seo_not_configured`).

  `output` always holds `"sources"` (the sources read, in priority order:
  `"#{@search_console}"`, or `"#{@ranked_phrases}"` and `"#{@first_pages}"`),
  `"matched"` and `"quick_wins"`. From Search Console it adds the `"rows"`
  and the `"start_date"` and `"end_date"` of the window; otherwise
  `"search_console"` says why Search Console was not used, and
  `"ranked_phrases_unavailable"` why the ranked phrases were not read, when
  they were not.
  """
  def fetch(%Run{mode: :new_idea}), do: {:skip, @new_idea_result}

  def fetch(%Run{} = run) do
    case Positions.rows(run) do
      {:ok, %{rows: [_row | _rows]} = answer} -> from_search_console(run, answer)
      {:ok, %{rows: []}} -> from_google_results(run, @no_search_console_rows)
      {:unavailable, reason_line} -> from_google_results(run, reason_line)
      {:error, reason} -> {:error, reason}
    end
  end

  defp from_search_console(run, %{rows: rows, window: window}) do
    {:ok, counts} =
      Phrases.store_current_positions(run, Enum.map(rows, &%{phrase: &1.query, position: &1.position}))

    output =
      [@search_console]
      |> output(counts)
      |> Map.merge(%{
        "rows" => Enum.map(rows, &stored_search_console_row/1),
        "start_date" => Date.to_iso8601(window.start_date),
        "end_date" => Date.to_iso8601(window.end_date)
      })

    {:ok, %{result: result_line(counts, @search_console), output: output}}
  end

  defp from_google_results(run, search_console_line) do
    with {:ok, ranked} <- ranked_phrases(run) do
      rows = ranked.rows ++ first_page_rows(run, ranked.rows)
      {:ok, counts} = Phrases.store_current_positions(run, rows)

      output =
        ranked.sources
        |> output(counts)
        |> Map.put("search_console", search_console_line)
        |> Map.merge(ranked.unavailable)

      {:ok, %{result: result_line(counts, hd(ranked.sources)), output: output}}
    end
  end

  defp ranked_phrases(run) do
    paid_request = %{
      service: "dataforseo",
      operation: "ranked_phrases",
      request: %{
        domain: Run.ascii_domain(run),
        location_code: run.location_code,
        language_code: run.language_code,
        limit: Application.fetch_env!(:dirmoon, :ranked_phrases_limit)
      }
    }

    case Ledger.fetch(run, paid_request, fn -> buy_ranked_phrases(paid_request.request) end) do
      {:ok, %{"rows" => rows}} ->
        {:ok, %{rows: Enum.map(rows, &ranked_row/1), sources: [@ranked_phrases, @first_pages], unavailable: %{}}}

      {:ok, %{"unavailable" => reason}} ->
        first_pages_only(reason)

      {:error, :not_in_demo_data} ->
        first_pages_only(@not_in_demo_data)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp first_pages_only(reason),
    do: {:ok, %{rows: [], sources: [@first_pages], unavailable: %{"ranked_phrases_unavailable" => reason}}}

  defp buy_ranked_phrases(request) do
    case DataForSEO.ranked_phrases(request) do
      {:ok, %{rows: rows, raw: raw, cost: cost}} ->
        stored_rows = Enum.map(rows, &%{"phrase" => &1.phrase, "position" => &1.position, "url" => &1.url})
        {:ok, %{"rows" => stored_rows, "raw" => raw}, cost}

      {:error, {:ranked_phrases_unavailable, %{message: message, raw: raw, cost: cost}}} ->
        {:ok, %{"unavailable" => message, "raw" => raw}, cost}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ranked_row(%{"phrase" => phrase, "position" => position, "url" => url}),
    do: %{phrase: phrase, position: position, url: url}

  defp first_page_rows(run, ranked_rows) do
    ranked_phrases = MapSet.new(ranked_rows, &Phrase.normalise(&1.phrase))
    assessments = Competition.assessments_for_run(run)

    run
    |> Phrases.list_for_run()
    |> Enum.reject(&MapSet.member?(ranked_phrases, Phrase.normalise(&1.phrase.phrase)))
    |> Enum.flat_map(fn run_phrase ->
      assessments
      |> Map.get(run_phrase.keyword_id)
      |> site_results(Run.ascii_domain(run))
      |> Enum.map(&%{phrase: run_phrase.phrase.phrase, position: &1["position"], url: &1["url"]})
    end)
  end

  defp site_results(nil, _domain), do: []

  defp site_results(assessment, domain), do: Enum.filter(assessment.serp_snapshot.results, &site?(&1, domain))

  defp site?(%{"domain" => host}, domain) when is_binary(host), do: HostName.bare(host) == domain

  defp site?(_result, _domain), do: false

  defp result_line(%{matched: 0}, @first_pages), do: @not_on_first_pages_result
  defp result_line(%{matched: 0}, _source), do: @not_found_result

  defp result_line(%{matched: matched, quick_wins: quick_wins}, source) do
    range = Phrases.quick_win_range()

    "#{matched} #{Format.plural(matched, @phrase_forms)} where your site shows up on Google, " <>
      "#{quick_wins} at positions #{range.first}–#{range.last} (from #{Map.fetch!(@source_names, source)})"
  end

  defp output(sources, %{matched: matched, quick_wins: quick_wins}),
    do: %{"sources" => sources, "matched" => matched, "quick_wins" => quick_wins}

  defp stored_search_console_row(row) do
    %{
      "query" => row.query,
      "clicks" => row.clicks,
      "impressions" => row.impressions,
      "ctr" => row.ctr,
      "position" => row.position
    }
  end
end
