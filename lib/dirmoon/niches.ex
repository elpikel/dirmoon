defmodule Dirmoon.Niches do
  @moduledoc """
  Niches: the groups of a Research Run's Phrases that share a search intent,
  stored in `clusters`. Per run, so per Account; callers pass a `%Run{}` they
  already resolved through the Scope, and functions that take a Niche id
  take the `Scope` and only see the Scope's Account's Niches (a foreign id is
  not found and changes nothing).
  """

  import Ecto.Query

  alias Dirmoon.Accounts.Scope
  alias Dirmoon.Competition
  alias Dirmoon.Niches.Niche
  alias Dirmoon.Pages
  alias Dirmoon.Pages.Page
  alias Dirmoon.Phrases
  alias Dirmoon.Repo
  alias Dirmoon.Research
  alias Dirmoon.Research.Pipeline
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.Steps

  @omitted_reason "pominięta przez model"
  @empty_market_totals %{volume: 0, cpc: nil, keyword_ids: []}
  @brief_step Steps.number!(:brief_and_content)

  @doc """
  Stores Step 4's answer for the run in one transaction, replacing whatever
  an earlier pass stored: the run's Niches are deleted and its Phrases kept
  again first, so storing twice never duplicates anything.

  `grouping` is `%{niches: [%{name:, intent:, reading:, phrase_ids:}], rejected: [%{phrase_id:, reason:}]}`
  with RunPhrase ids; Niches get their `position` from the list order.
  Rejected Phrases get their reason, and every Phrase of the run the grouping
  doesn't mention is rejected as "#{@omitted_reason}".

  Returns `{:ok, %{niches: count, kept: phrases_in_niches, rejected: rejected_phrases}}`.
  """
  def store_grouping(%Run{} = run, %{niches: niches, rejected: rejected}) when is_list(niches) and is_list(rejected) do
    Repo.transact(fn ->
      delete_for_run(run)
      Phrases.clear_grouping(run)

      kept =
        run
        |> insert_niches(niches)
        |> Enum.map(&Phrases.assign_to_niche(run, &1))
        |> Enum.sum()

      rejected_by_model =
        rejected
        |> Enum.group_by(& &1.reason, & &1.phrase_id)
        |> Enum.map(fn {reason, phrase_ids} -> Phrases.reject(run, %{phrase_ids: phrase_ids, reason: reason}) end)
        |> Enum.sum()

      omitted = Phrases.reject_ungrouped(run, @omitted_reason)

      {:ok, %{niches: length(niches), kept: kept, rejected: rejected_by_model + omitted}}
    end)
  end

  @doc """
  The run's Niches, highest Score first, unscored ones last in the order the
  model returned them, each with `phrase_count` set.
  """
  def list_for_run(%Run{id: run_id}) do
    Niche
    |> from(as: :niche)
    |> join(:left, [niche: niche], run_phrase in assoc(niche, :run_phrases), as: :run_phrase)
    |> where([niche: niche], niche.run_id == ^run_id)
    |> group_by([niche: niche], niche.id)
    |> order_by([niche: niche], desc_nulls_last: niche.score, asc: niche.position)
    |> select_merge([run_phrase: run_phrase], %{phrase_count: count(run_phrase.id)})
    |> Repo.all()
  end

  @doc """
  The run's Niches as the results screen lists them, in `list_for_run/1`'s
  order (rejected ones included; `Niche.choosable?/1` tells them apart),
  each with the market totals of its kept Phrases
  (`Dirmoon.Phrases.market_totals_by_niche/1`: monthly country `volume` and
  Volume-weighted `cpc`) and the `competition` pooled over the top 10s of its
  assessed Phrases: the verdict and who holds them, nil when none of its
  Phrases was checked. Three queries, whatever the number of Niches.

  Returns `[%{niche: %Niche{}, volume: integer, cpc: Decimal | nil, competition: %{verdict: atom, holders: String.t()} | nil}]`.
  """
  def list_summaries(%Run{} = run) do
    assessment_summaries = Competition.assessment_summaries_for_run(run)
    market_totals = Phrases.market_totals_by_niche(run)

    run
    |> list_for_run()
    |> Enum.map(fn niche ->
      totals = Map.get(market_totals, niche.id, @empty_market_totals)

      %{
        niche: niche,
        volume: totals.volume,
        cpc: totals.cpc,
        competition: pooled_competition(totals.keyword_ids, assessment_summaries)
      }
    end)
  end

  @doc """
  What the results screen shows of one of the run's Niches: its kept
  Phrases, highest country Volume first, each with its country and city
  Volume, CPC, who holds its top 10 (nil when it wasn't checked) and the
  site's Current Position and whether that makes it a Quick Win; the most
  direct competitors found in one checked Phrase's top 10 (nil when none was
  checked); the best Current Position of its Phrases (nil when none ranks);
  how many of its Phrases are Quick Wins; and the Niche's page, if it has one.

  Returns `%{phrases: [%{id:, phrase:, volume:, city_volume:, cpc:, currency:, holders:, current_position:, quick_win?:}], direct_competitors: integer | nil, best_position: Decimal | nil, quick_win_count: integer, page: %Page{} | nil}`.
  """
  def niche_detail(%Run{id: run_id} = run, %Niche{id: niche_id, run_id: run_id} = niche) do
    assessment_summaries = Competition.assessment_summaries_for_run(run)
    run_phrases = Phrases.list_for_run(run, %{niche_id: niche_id})

    %{
      phrases: Enum.map(run_phrases, &phrase_detail(&1, assessment_summaries)),
      direct_competitors: most_direct_competitors(run_phrases, assessment_summaries),
      best_position: best_position(run_phrases),
      quick_win_count: Enum.count(run_phrases, &Phrases.quick_win?(&1.current_position)),
      page: Pages.page_for_niche(niche)
    }
  end

  @doc """
  What Step 7 scores each proposed Niche of the run on, from its kept
  Phrases: `volume` and `cpc` from `Dirmoon.Phrases.market_totals_by_niche/1`
  (0 and nil for a Niche without kept Phrases) and `weak_share` the share of blogs, forums and directories among all the
  labelled top-10 results of their SERP Assessments
  (`Dirmoon.Competition.weak_share/1`), nil when none was assessed.

  Returns `[%{niche_id:, volume:, cpc: Decimal | nil, weak_share: float | nil}]` in position order.
  """
  def niche_aggregates(%Run{} = run) do
    assessments = Competition.assessments_for_run(run)
    market_totals = Phrases.market_totals_by_niche(run)

    run
    |> proposed_niche_ids()
    |> Enum.map(fn niche_id ->
      totals = Map.get(market_totals, niche_id, @empty_market_totals)

      %{
        niche_id: niche_id,
        volume: totals.volume,
        cpc: totals.cpc,
        weak_share: pooled_weak_share(totals.keyword_ids, assessments)
      }
    end)
  end

  @doc """
  Stores Step 7's Scores (`[%{niche_id:, score:, components:}]`) in one
  statement. Only the run's own Niches are written.

  Returns `{:ok, count}` with the number of Niches written.
  """
  def store_scores(%Run{id: run_id}, scores) when is_list(scores) do
    {written, _rows} =
      Niche
      |> from(as: :niche)
      |> join(
        :inner,
        [niche: niche],
        score in fragment(
          "SELECT * FROM unnest(?::bigint[], ?::numeric[], ?::jsonb[]) AS score(niche_id, score, components)",
          type(^Enum.map(scores, & &1.niche_id), {:array, :id}),
          type(^Enum.map(scores, & &1.score), {:array, :decimal}),
          type(^Enum.map(scores, & &1.components), {:array, :map})
        ),
        as: :score,
        on: score.niche_id == niche.id
      )
      |> where([niche: niche], niche.run_id == ^run_id)
      |> update([score: score],
        set: [score: score.score, score_components: score.components, updated_at: ^DateTime.utc_now(:second)]
      )
      |> Repo.update_all([])

    {:ok, written}
  end

  @doc """
  The Scope's Account's Niche with the given id, or nil (a malformed or
  foreign id is nil).
  """
  def get_niche(%Scope{} = scope, id) do
    case Ecto.Type.cast(:id, id) do
      {:ok, niche_id} ->
        scope
        |> account_niches_query()
        |> where([niche: niche], niche.id == ^niche_id)
        |> Repo.one()

      :error ->
        nil
    end
  end

  @doc """
  The User picks a Niche to write a page for. In one transaction, with the
  run locked: the Niche is marked chosen, its page is created `:writing` (or
  a `:failed` one is set `:writing` again) and Step 8 is enqueued
  (`Dirmoon.Research.Pipeline.start_step/2`); subscribers to the page
  and, when Step 8 started, to the run are told once it commits.

  A Niche that already has a page that hasn't failed (being written,
  written, being published or published) returns that page and enqueues
  nothing. Otherwise a Niche of the run must be choosable now
  (`Dirmoon.Research.Run.choosable?/1`: Step 7 is done and the run isn't
  stopped, else `:run_not_ready`); the Niche must be proposed or chosen
  (`Niche.choosable?/1`, else `:not_choosable`); no other page of the run
  may be `:writing` (else `:brief_in_progress`); and the run must be idle
  (`Dirmoon.Research.idle?/1`: not running, no Step 8 or 9 queued or
  running, else `:run_busy`).

  Returns `{:ok, page}` or
  `{:error, :not_found | :run_not_ready | :not_choosable | :brief_in_progress | :run_busy}`.
  """
  def choose(%Scope{} = scope, niche_id) do
    with %Niche{} = niche <- get_niche(scope, niche_id) || {:error, :not_found},
         {:ok, %{page: page, run: run, started?: started?}} <- Repo.transact(fn -> choose_in_locked_run(niche) end) do
      Pages.broadcast_page_updated(page)
      if started?, do: Research.broadcast_run_updated(run)
      {:ok, page}
    end
  end

  @doc """
  The User drops a proposed Niche.

  Returns `{:ok, niche}` or `{:error, :not_found | :not_rejectable}`.
  """
  def reject(%Scope{} = scope, niche_id) do
    with %Niche{id: id} <- get_niche(scope, niche_id) || {:error, :not_found} do
      Niche
      |> from(as: :niche)
      |> where([niche: niche], niche.id == ^id and niche.status == ^:proposed)
      |> select([niche: niche], niche)
      |> Repo.update_all(set: [status: :rejected, updated_at: DateTime.utc_now(:second)])
      |> case do
        {1, [rejected_niche]} -> {:ok, rejected_niche}
        {0, []} -> {:error, :not_rejectable}
      end
    end
  end

  defp account_niches_query(%Scope{account: account}) do
    Niche
    |> from(as: :niche)
    |> join(:inner, [niche: niche], run in assoc(niche, :run), as: :run)
    |> where([run: run], run.account_id == ^account.id)
  end

  defp choose_in_locked_run(%Niche{id: niche_id, run_id: run_id}) do
    run = Research.lock_run!(run_id)
    niche = Repo.get!(Niche, niche_id)

    case Pages.page_for_niche(niche) do
      %Page{status: :failed} = failed_page -> start_writing(run, %{niche: niche, page: failed_page})
      %Page{} = kept_page -> {:ok, %{page: kept_page, run: run, started?: false}}
      nil -> start_writing(run, %{niche: niche, page: nil})
    end
  end

  defp ensure_run_choosable(run) do
    if Run.choosable?(run), do: :ok, else: {:error, :run_not_ready}
  end

  defp ensure_run_idle(run) do
    if Research.idle?(run), do: :ok, else: {:error, :run_busy}
  end

  defp ensure_choosable(niche) do
    if Niche.choosable?(niche), do: :ok, else: {:error, :not_choosable}
  end

  defp ensure_no_brief_in_progress(run) do
    case Pages.writing_page_for_run(run) do
      nil -> :ok
      %Page{} -> {:error, :brief_in_progress}
    end
  end

  defp start_writing(run, %{niche: niche} = choice) do
    with :ok <- ensure_run_choosable(run),
         :ok <- ensure_choosable(niche),
         :ok <- ensure_no_brief_in_progress(run),
         :ok <- ensure_run_idle(run),
         {:ok, page} <- write_page(run, choice),
         {:ok, updated_run} <- Pipeline.start_step(run, @brief_step) do
      niche |> Ecto.Changeset.change(status: :chosen) |> Repo.update!()
      {:ok, %{page: page, run: updated_run, started?: true}}
    end
  end

  defp write_page(run, %{niche: niche, page: nil}), do: Pages.create_for_niche(run, niche)
  defp write_page(_run, %{page: %Page{status: :failed} = failed_page}), do: Pages.restart_writing(failed_page)

  defp proposed_niche_ids(%Run{id: run_id}) do
    Niche
    |> from(as: :niche)
    |> where([niche: niche], niche.run_id == ^run_id and niche.status == ^:proposed)
    |> order_by([niche: niche], asc: niche.position)
    |> select([niche: niche], niche.id)
    |> Repo.all()
  end

  defp pooled_weak_share(keyword_ids, assessments) do
    keyword_ids
    |> Enum.flat_map(fn keyword_id ->
      case Map.fetch(assessments, keyword_id) do
        {:ok, assessment} -> assessment.labels
        :error -> []
      end
    end)
    |> Competition.weak_share()
  end

  defp pooled_competition(keyword_ids, assessment_summaries) do
    case assessments_of(keyword_ids, assessment_summaries) do
      [] ->
        nil

      assessed ->
        labels = Enum.flat_map(assessed, & &1.labels)
        %{verdict: Competition.verdict(labels), holders: Competition.holders(labels)}
    end
  end

  defp assessments_of(keyword_ids, assessment_summaries) do
    keyword_ids
    |> Enum.map(&Map.get(assessment_summaries, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp phrase_detail(run_phrase, assessment_summaries) do
    assessment = Map.get(assessment_summaries, run_phrase.keyword_id)

    %{
      id: run_phrase.id,
      phrase: run_phrase.phrase.phrase,
      volume: run_phrase.metrics && run_phrase.metrics.search_volume,
      city_volume: run_phrase.city_metrics && run_phrase.city_metrics.search_volume,
      cpc: run_phrase.metrics && run_phrase.metrics.cpc,
      currency: run_phrase.metrics && run_phrase.metrics.currency,
      holders: assessment && Competition.holders(assessment.labels),
      current_position: run_phrase.current_position,
      quick_win?: Phrases.quick_win?(run_phrase.current_position)
    }
  end

  defp most_direct_competitors(run_phrases, assessment_summaries) do
    run_phrases
    |> Enum.map(& &1.keyword_id)
    |> assessments_of(assessment_summaries)
    |> Enum.map(&Competition.direct_competitor_count(&1.labels))
    |> Enum.max(fn -> nil end)
  end

  defp best_position(run_phrases) do
    run_phrases
    |> Enum.map(& &1.current_position)
    |> Enum.reject(&is_nil/1)
    |> Enum.min(Decimal, fn -> nil end)
  end

  defp delete_for_run(%Run{id: run_id}) do
    Niche
    |> from(as: :niche)
    |> where([niche: niche], niche.run_id == ^run_id)
    |> Repo.delete_all()
  end

  defp insert_niches(_run, []), do: []

  defp insert_niches(%Run{id: run_id}, niches) do
    now = DateTime.utc_now(:second)
    positioned_niches = Enum.with_index(niches, 1)

    {_count, inserted} =
      Repo.insert_all(
        Niche,
        Enum.map(positioned_niches, fn {niche, position} ->
          %{
            run_id: run_id,
            name: niche.name,
            intent: niche.intent,
            reading: niche.reading,
            status: :proposed,
            position: position,
            inserted_at: now,
            updated_at: now
          }
        end),
        returning: [:id, :position]
      )

    niche_ids_by_position = Map.new(inserted, &{&1.position, &1.id})

    Enum.map(positioned_niches, fn {niche, position} ->
      %{niche_id: Map.fetch!(niche_ids_by_position, position), phrase_ids: niche.phrase_ids}
    end)
  end
end
