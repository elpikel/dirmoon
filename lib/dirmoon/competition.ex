defmodule Dirmoon.Competition do
  @moduledoc """
  Who holds Google's top 10 for a Phrase. SERP Snapshots
  (`serp_snapshots`) are shared market data (ADR-0002), reused across runs
  while younger than `config :dirmoon, serp_max_age_days:`. A run's judgement
  of a snapshot, the Page Type of each result and the verdict, is a
  SERP Assessment (`serp_assessments`), stored per run.

  Labels are lists of maps with `"position"` and `"page_type"` (a Page Type
  from `SerpAssessment.page_types/0`, as a string).
  """

  import Ecto.Query

  alias Dirmoon.Competition.SerpAssessment
  alias Dirmoon.Competition.SerpSnapshot
  alias Dirmoon.Format
  alias Dirmoon.Repo
  alias Dirmoon.Research.Run

  @strong_direct_competitors 5
  @checked_forms %{one: "phrase checked", other: "phrases checked"}
  @no_holders "no results"
  @direct_competitor Atom.to_string(SerpAssessment.direct_competitor())
  @weak_page_types Enum.map(SerpAssessment.weak_page_types(), &Atom.to_string/1)
  @names_by_page_type Map.new(SerpAssessment.page_type_names(), fn {page_type, name} ->
                        {Atom.to_string(page_type), {page_type, name}}
                      end)
  @plurals_by_page_type Map.new(SerpAssessment.page_type_plurals(), fn {page_type, plural} ->
                          {Atom.to_string(page_type), plural}
                        end)

  @doc """
  The freshest SERP Snapshot of the Phrase in the location fetched in the
  last `serp_max_age_days` days, by any run, or nil.
  """
  def fresh_snapshot(keyword_id, location_code) when is_integer(keyword_id) and is_integer(location_code) do
    fresh_since = DateTime.shift(DateTime.utc_now(:second), day: -max_age_days())

    SerpSnapshot
    |> from(as: :serp_snapshot)
    |> where(
      [serp_snapshot: serp_snapshot],
      serp_snapshot.keyword_id == ^keyword_id and serp_snapshot.location_code == ^location_code and
        serp_snapshot.fetched_at >= ^fresh_since
    )
    |> order_by([serp_snapshot: serp_snapshot], desc: serp_snapshot.fetched_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Stores a fetched top 10 as a SERP Snapshot. A snapshot of the same Phrase,
  location and `fetched_at` is the same fetch (a ledger replay), so it is
  returned instead of being stored twice.
  """
  def store_snapshot(%{keyword_id: keyword_id, location_code: location_code, fetched_at: fetched_at} = attrs) do
    SerpSnapshot
    |> struct(Map.take(attrs, [:keyword_id, :location_code, :language_code, :fetched_at, :results, :raw]))
    |> Repo.insert!(on_conflict: :nothing, conflict_target: [:keyword_id, :location_code, :fetched_at])
    |> case do
      %SerpSnapshot{id: nil} ->
        Repo.get_by!(SerpSnapshot, keyword_id: keyword_id, location_code: location_code, fetched_at: fetched_at)

      %SerpSnapshot{} = snapshot ->
        snapshot
    end
  end

  @doc """
  Stores the run's assessment of a Phrase's snapshot
  (`%{keyword_id:, serp_snapshot_id:, labels:, verdict:, reused_snapshot:}`).
  A Phrase the run already assessed keeps its first assessment.
  """
  def store_assessment(%Run{id: run_id}, attrs) do
    %SerpAssessment{run_id: run_id}
    |> struct(Map.take(attrs, [:keyword_id, :serp_snapshot_id, :labels, :verdict, :reused_snapshot]))
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:run_id, :keyword_id])
  end

  @doc """
  The run's SERP Assessments by Phrase id (`keyword_id`), each with its
  `serp_snapshot` (and so the results) preloaded.
  """
  def assessments_for_run(%Run{id: run_id}) do
    SerpAssessment
    |> from(as: :serp_assessment)
    |> join(:inner, [serp_assessment: serp_assessment], serp_snapshot in assoc(serp_assessment, :serp_snapshot),
      as: :serp_snapshot
    )
    |> where([serp_assessment: serp_assessment], serp_assessment.run_id == ^run_id)
    |> preload([serp_snapshot: serp_snapshot], serp_snapshot: serp_snapshot)
    |> Repo.all()
    |> Map.new(&{&1.keyword_id, &1})
  end

  @doc """
  A summary of each of the run's SERP Assessments, by Phrase id
  (`keyword_id`): its verdict and labels, without the snapshots. One query.

  Returns `%{keyword_id => %{verdict: atom, labels: [map]}}`.
  """
  def assessment_summaries_for_run(%Run{id: run_id}) do
    SerpAssessment
    |> from(as: :serp_assessment)
    |> where([serp_assessment: serp_assessment], serp_assessment.run_id == ^run_id)
    |> select([serp_assessment: serp_assessment], {
      serp_assessment.keyword_id,
      %{verdict: serp_assessment.verdict, labels: serp_assessment.labels}
    })
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  How many results of a labelled top 10 are direct competitors.
  """
  def direct_competitor_count(labels) when is_list(labels) do
    Enum.count(labels, &(&1["page_type"] == @direct_competitor))
  end

  @doc """
  The competition verdict for a labelled top 10: `:weak` when blogs, forums
  and directories hold more than half of the labelled results (or there are
  no results), `:strong` when direct competitors hold more than half or at
  least #{@strong_direct_competitors}, `:medium` otherwise.
  """
  def verdict([]), do: :weak

  def verdict(labels) when is_list(labels) do
    labelled = length(labels)
    direct_competitors = direct_competitor_count(labels)

    cond do
      weak_count(labels) * 2 > labelled -> :weak
      direct_competitors * 2 > labelled or direct_competitors >= @strong_direct_competitors -> :strong
      true -> :medium
    end
  end

  @doc """
  Who holds the top 10: the plurals of the two most common Page Types, ties
  going to the type ranked higher (`"guides and blogs, forums"`), or
  `"#{@no_holders}"` when there are no results.
  """
  def holders([]), do: @no_holders

  def holders(labels) when is_list(labels) do
    labels
    |> Enum.group_by(& &1["page_type"], & &1["position"])
    |> Enum.sort_by(fn {_page_type, positions} -> {-length(positions), Enum.min(positions)} end)
    |> Enum.take(2)
    |> Enum.map_join(", ", fn {page_type, _positions} -> Map.fetch!(@plurals_by_page_type, page_type) end)
  end

  @doc """
  Google's first page as a SERP Assessment (with its `serp_snapshot` loaded)
  saw it: the snapshot's results in position order, each with the Page Type
  the run gave it and its name (both nil for a result left unlabelled).

  Returns `[%{position:, domain:, url:, title:, page_type: atom | nil, page_type_name: String.t() | nil}]`.
  """
  def first_page(%SerpAssessment{labels: labels, serp_snapshot: %SerpSnapshot{results: results}}) do
    page_types = Map.new(labels, &{&1["position"], &1["page_type"]})

    results
    |> Enum.sort_by(& &1["position"])
    |> Enum.map(fn result ->
      {page_type, name} = Map.get(@names_by_page_type, Map.get(page_types, result["position"]), {nil, nil})

      %{
        position: result["position"],
        domain: result["domain"],
        url: result["url"],
        title: result["title"],
        page_type: page_type,
        page_type_name: name
      }
    end)
  end

  @doc """
  How many of the Phrases picked for the competition check are checked:
  `"4 of 10 phrases checked"`, `"1 of 1 phrase checked"`.
  """
  def checked_line(checked, total) when is_integer(checked) and is_integer(total) do
    "#{checked} of #{total} #{Format.plural(total, @checked_forms)}"
  end

  @doc """
  The share (0.0–1.0) of labelled results held by blogs, forums and
  directories, or nil when nothing is labelled.
  """
  def weak_share([]), do: nil
  def weak_share(labels) when is_list(labels), do: weak_count(labels) / length(labels)

  defp weak_count(labels), do: Enum.count(labels, &(&1["page_type"] in @weak_page_types))

  defp max_age_days, do: Application.fetch_env!(:dirmoon, :serp_max_age_days)
end
