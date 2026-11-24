defmodule Dirmoon.Phrases do
  @moduledoc """
  Phrases and their Volumes. Phrases (`keywords`) and Volumes
  (`keyword_metrics`) are shared market data stored once for all Accounts
  (ADR-0002); which Phrases a Research Run has, and what it decided about
  them, lives per run in `run_keywords`.
  """

  import Ecto.Query

  alias Dirmoon.Competition
  alias Dirmoon.Phrases.Phrase
  alias Dirmoon.Phrases.RunPhrase
  alias Dirmoon.Phrases.Volume
  alias Dirmoon.Repo
  alias Dirmoon.Research.Run

  @insert_chunk_size 1000
  @volume_max_age_days 30
  @missing_volume_currency "USD"
  @quick_win_range 8..20

  @doc """
  Stores what Expansion returned for a run: upserts the shared Phrases, links
  them to the run with origin `:expansion` and upserts their Volume for the
  run's country (`run.location_code`). `rows` are the keyword API's rows
  (`%{phrase:, search_volume:, cpc:, currency:, monthly_searches:, fetched_at:}`),
  possibly from several batches, each with the time its batch was really
  fetched; a Phrase listed twice is stored once (first row wins). A row
  replaces a stored Volume only when it was fetched later, so an older fetch
  never overwrites newer data nor makes it look fresh. Calling it again with
  the same rows changes nothing.

  Returns `{:ok, count}` with the number of distinct Phrases in `rows`.
  """
  def store_expansion(%Run{} = run, rows) when is_list(rows) do
    rows_by_phrase = distinct_rows_by_phrase(rows)

    Repo.transact(fn ->
      phrase_ids = upsert_phrases(Map.keys(rows_by_phrase), run.language_code)
      now = DateTime.utc_now(:second)

      rows_by_phrase
      |> Enum.map(fn {phrase, row} -> %{keyword_id: Map.fetch!(phrase_ids, phrase), row: row} end)
      |> upsert_volumes(run.location_code, now)

      link_to_run(%{run: run, phrase_ids: Map.values(phrase_ids), origin: :expansion}, now)

      {:ok, map_size(rows_by_phrase)}
    end)
  end

  @doc """
  The run's Phrases with `phrase` preloaded, `volume` set to the Volume for
  the run's country and `city_volume` to the Volume for the run's city
  location (`nil` when there is none, or the run has no city location),
  highest country Volume first, then by text. One query.

  `filters` narrows the list: `status: :kept | :rejected`, `niche_id:` (the
  kept Phrases of that Niche) and `limit:` (at most that many).
  """
  def list_for_run(%Run{} = run, filters \\ %{}) when is_map(filters) do
    run
    |> list_query()
    |> filter_list(filters)
    |> Repo.all()
  end

  @doc """
  The run's kept Phrases that have no Volume for `location_code` fetched in
  the last #{@volume_max_age_days} days (by any run), oldest Phrase first.
  """
  def phrases_needing_volume(%Run{id: run_id}, location_code) when is_integer(location_code) do
    fresh_since = DateTime.shift(DateTime.utc_now(:second), day: -@volume_max_age_days)

    RunPhrase
    |> from(as: :run_phrase)
    |> join(:inner, [run_phrase: run_phrase], phrase in assoc(run_phrase, :phrase), as: :phrase)
    |> join_location_volume(location_code)
    |> where([run_phrase: run_phrase], run_phrase.run_id == ^run_id and run_phrase.status == ^:kept)
    |> where([volume: volume], is_nil(volume.id) or volume.fetched_at < ^fresh_since)
    |> order_by([phrase: phrase], asc: phrase.id)
    |> select([phrase: phrase], phrase)
    |> Repo.all()
  end

  @doc """
  Stores the Volumes a search volumes request returned for `location_code`.
  `rows` (`%{phrase:, search_volume:, cpc:, currency:, monthly_searches:, fetched_at:}`)
  are matched to the asked `phrases` by normalised phrase; a row for a Phrase
  that wasn't asked is ignored, and an asked Phrase without a row gets an
  empty Volume fetched at `fetched_at`, so it isn't asked again while fresh.
  Same conditional upsert as `store_expansion/2`.

  Returns `{:ok, count}` with the number of asked Phrases.
  """
  def store_volumes(location_code, %{phrases: phrases, rows: rows, fetched_at: fetched_at})
      when is_integer(location_code) and is_list(phrases) and is_list(rows) do
    rows_by_phrase = distinct_rows_by_phrase(rows)
    asked_phrases = Enum.uniq_by(phrases, & &1.id)

    asked_phrases
    |> Enum.map(fn %Phrase{id: keyword_id, phrase: phrase} ->
      %{keyword_id: keyword_id, row: Map.get_lazy(rows_by_phrase, phrase, fn -> missing_row(phrase, fetched_at) end)}
    end)
    |> upsert_volumes(location_code, DateTime.utc_now(:second))

    {:ok, length(asked_phrases)}
  end

  @doc """
  The run's kept Phrases that are in a Niche, at most `limit`, highest
  country Volume (`run.location_code`) first, Phrases without a Volume last,
  then by text.
  """
  def top_kept_in_niches(%Run{id: run_id, location_code: location_code}, limit) when is_integer(limit) and limit > 0 do
    RunPhrase
    |> from(as: :run_phrase)
    |> join(:inner, [run_phrase: run_phrase], phrase in assoc(run_phrase, :phrase), as: :phrase)
    |> join_location_volume(location_code)
    |> where([run_phrase: run_phrase], run_phrase.run_id == ^run_id and run_phrase.status == ^:kept)
    |> where([run_phrase: run_phrase], not is_nil(run_phrase.cluster_id))
    |> order_by([phrase: phrase, volume: volume], desc_nulls_last: volume.search_volume, asc: phrase.phrase)
    |> limit(^limit)
    |> select([phrase: phrase], phrase)
    |> Repo.all()
  end

  @doc """
  The market totals of the run's kept Phrases, per Niche they are in:
  `volume` is the sum of their country Volumes (`run.location_code`,
  missing ones counted as 0), `cpc` their Volume-weighted average CPC over
  the Phrases that have one (the plain average when those Volumes sum to 0,
  nil when none has a CPC) and `keyword_ids` the Phrases' ids. A Niche
  without kept Phrases is absent.

  Returns `%{niche_id => %{volume: integer, cpc: Decimal | nil, keyword_ids: [id]}}`.
  """
  def market_totals_by_niche(%Run{id: run_id, location_code: location_code}) do
    RunPhrase
    |> from(as: :run_phrase)
    |> join_location_volume(location_code)
    |> where([run_phrase: run_phrase], run_phrase.run_id == ^run_id and run_phrase.status == ^:kept)
    |> where([run_phrase: run_phrase], not is_nil(run_phrase.cluster_id))
    |> group_by([run_phrase: run_phrase], run_phrase.cluster_id)
    |> select([run_phrase: run_phrase, volume: volume], {
      run_phrase.cluster_id,
      %{
        volume: type(coalesce(sum(volume.search_volume), 0), :integer),
        cpc:
          type(
            coalesce(
              sum(coalesce(volume.search_volume, 0) * volume.cpc) /
                fragment("nullif(?, 0)", filter(sum(coalesce(volume.search_volume, 0)), not is_nil(volume.cpc))),
              avg(volume.cpc)
            ),
            :decimal
          ),
        keyword_ids: fragment("array_agg(?)", run_phrase.keyword_id)
      }
    })
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  The run's Phrases as rows for an export, kept ones first, each by country
  Volume: the Phrase, its Niche's name, country and city Volume, CPC and its
  currency, the run's competition reading of its top 10
  (`Dirmoon.Competition`; nil when it wasn't checked), its Current Position
  and whether and why it was rejected. Nothing about the Account.

  Returns `[%{phrase:, niche:, country_volume:, city_volume:, cpc:, currency:, verdict:, holders:, current_position:, rejected?:, rejection_reason:}]`.
  """
  def export_rows(%Run{} = run) do
    readings = Competition.readings_for_run(run)

    run
    |> list_query()
    |> join(:left, [run_phrase: run_phrase], niche in assoc(run_phrase, :niche), as: :niche)
    |> preload([niche: niche], niche: niche)
    |> Repo.all()
    |> Enum.map(&export_row(&1, readings))
    |> Enum.sort_by(& &1.rejected?)
  end

  @doc """
  How many of the run's Phrases are kept and how many rejected.

  Returns `%{kept: count, rejected: count}`.
  """
  def count_by_status(%Run{} = run) do
    counts =
      run
      |> run_phrases_query()
      |> group_by([run_phrase: run_phrase], run_phrase.status)
      |> select([run_phrase: run_phrase], {run_phrase.status, count(run_phrase.id)})
      |> Repo.all()
      |> Map.new()

    statuses = RunPhrase.statuses()
    Map.new(statuses, &{&1, Map.get(counts, &1, 0)})
  end

  @doc "How many Phrases the run has."
  def count_for_run(%Run{id: run_id}) do
    RunPhrase
    |> from(as: :run_phrase)
    |> where([run_phrase: run_phrase], run_phrase.run_id == ^run_id)
    |> Repo.aggregate(:count)
  end

  @doc "How many Phrases the run kept."
  def count_kept_for_run(%Run{id: run_id}) do
    RunPhrase
    |> from(as: :run_phrase)
    |> where([run_phrase: run_phrase], run_phrase.run_id == ^run_id and run_phrase.status == ^:kept)
    |> Repo.aggregate(:count)
  end

  @doc """
  Undoes Step 4's decisions for the run: every Phrase of the run is kept
  again, without a reason and without a Niche.
  """
  def clear_grouping(%Run{} = run) do
    run
    |> run_phrases_query()
    |> Repo.update_all(
      set: [status: :kept, rejection_reason: nil, cluster_id: nil, updated_at: DateTime.utc_now(:second)]
    )

    :ok
  end

  @doc """
  Puts the run's Phrases with the given RunPhrase ids into the Niche. Ids of
  other runs' Phrases change nothing. Returns how many Phrases were assigned.
  """
  def assign_to_niche(%Run{} = run, %{niche_id: niche_id, phrase_ids: phrase_ids}) when is_list(phrase_ids) do
    {count, _rows} =
      run
      |> run_phrases_query()
      |> where([run_phrase: run_phrase], run_phrase.id in ^phrase_ids)
      |> Repo.update_all(set: [cluster_id: niche_id, updated_at: DateTime.utc_now(:second)])

    count
  end

  @doc """
  Makes the run's Phrases with the given RunPhrase ids Rejected Phrases with
  the reason. Ids of other runs' Phrases change nothing. Returns how many
  Phrases were rejected.
  """
  def reject(%Run{} = run, %{phrase_ids: phrase_ids, reason: reason}) when is_list(phrase_ids) and is_binary(reason) do
    {count, _rows} =
      run
      |> run_phrases_query()
      |> where([run_phrase: run_phrase], run_phrase.id in ^phrase_ids)
      |> reject_all(reason)

    count
  end

  @doc """
  Rejects, with the reason, every kept Phrase of the run that isn't in a
  Niche. Returns how many Phrases were rejected.
  """
  def reject_ungrouped(%Run{} = run, reason) when is_binary(reason) do
    {count, _rows} =
      run
      |> run_phrases_query()
      |> where([run_phrase: run_phrase], run_phrase.status == ^:kept and is_nil(run_phrase.cluster_id))
      |> reject_all(reason)

    count
  end

  @doc """
  The Current Positions on which a Phrase is cheapest to push up.
  """
  def quick_win_range, do: @quick_win_range

  @doc """
  Sets the run's Current Positions from Search Console `rows`
  (`%{query:, position:}`): each row is matched to the run's Phrases (kept
  or rejected) by normalised text, a query listed twice keeps its best
  position, and the position is stored rounded to one decimal. The run's
  other Phrases lose any earlier position, so running it again replaces the
  previous positions.

  Returns `{:ok, %{matched: count, quick_wins: count}}`, quick wins being the
  matched Phrases within `quick_win_range/0`.
  """
  def store_current_positions(%Run{} = run, rows) when is_list(rows) do
    best_positions = best_positions_by_phrase(rows)

    Repo.transact(fn ->
      run
      |> run_phrases_query()
      |> where([run_phrase: run_phrase], not is_nil(run_phrase.current_position))
      |> Repo.update_all(set: [current_position: nil, updated_at: DateTime.utc_now(:second)])

      stored_positions = update_current_positions(run, best_positions)

      {:ok, %{matched: length(stored_positions), quick_wins: Enum.count(stored_positions, &quick_win?/1)}}
    end)
  end

  defp best_positions_by_phrase(rows) do
    rows
    |> Enum.map(&%{phrase: Phrase.normalise(&1.query), position: rounded_position(&1.position)})
    |> Enum.reject(&(&1.phrase == ""))
    |> Enum.group_by(& &1.phrase, & &1.position)
    |> Map.new(fn {phrase, positions} -> {phrase, Enum.min(positions, Decimal)} end)
  end

  defp rounded_position(position) when is_integer(position), do: position |> Decimal.new() |> Decimal.round(1)
  defp rounded_position(position) when is_float(position), do: position |> Decimal.from_float() |> Decimal.round(1)

  defp update_current_positions(_run, positions) when map_size(positions) == 0, do: []

  defp update_current_positions(run, positions) do
    now = DateTime.utc_now(:second)

    {_count, stored_positions} =
      run
      |> run_phrases_query()
      |> join(:inner, [run_phrase: run_phrase], phrase in assoc(run_phrase, :phrase), as: :phrase)
      |> join(
        :inner,
        [phrase: phrase],
        position in fragment(
          "SELECT * FROM unnest(?::text[], ?::numeric[]) AS position(phrase, position)",
          ^Map.keys(positions),
          ^Map.values(positions)
        ),
        as: :position,
        on: position.phrase == phrase.phrase
      )
      |> update([position: position], set: [current_position: position.position, updated_at: ^now])
      |> select([run_phrase: run_phrase], run_phrase.current_position)
      |> Repo.update_all([])

    stored_positions
  end

  defp quick_win?(position) do
    Decimal.compare(position, @quick_win_range.first) != :lt and Decimal.compare(position, @quick_win_range.last) != :gt
  end

  defp run_phrases_query(%Run{id: run_id}) do
    RunPhrase
    |> from(as: :run_phrase)
    |> where([run_phrase: run_phrase], run_phrase.run_id == ^run_id)
  end

  defp reject_all(query, reason) do
    Repo.update_all(query,
      set: [status: :rejected, rejection_reason: reason, cluster_id: nil, updated_at: DateTime.utc_now(:second)]
    )
  end

  defp list_query(%Run{id: run_id, location_code: location_code} = run) do
    RunPhrase
    |> from(as: :run_phrase)
    |> join(:inner, [run_phrase: run_phrase], phrase in assoc(run_phrase, :phrase), as: :phrase)
    |> join_location_volume(location_code)
    |> merge_city_volume(run)
    |> where([run_phrase: run_phrase], run_phrase.run_id == ^run_id)
    |> order_by([phrase: phrase, volume: volume], desc_nulls_last: volume.search_volume, asc: phrase.phrase)
    |> preload([phrase: phrase], phrase: phrase)
    |> select_merge([volume: volume], %{volume: volume})
  end

  defp filter_list(query, filters) do
    Enum.reduce(filters, query, fn
      {:status, status}, filtered ->
        where(filtered, [run_phrase: run_phrase], run_phrase.status == ^status)

      {:niche_id, niche_id}, filtered ->
        where(filtered, [run_phrase: run_phrase], run_phrase.cluster_id == ^niche_id and run_phrase.status == ^:kept)

      {:limit, count}, filtered ->
        limit(filtered, ^count)
    end)
  end

  defp export_row(%RunPhrase{} = run_phrase, readings) do
    reading = Map.get(readings, run_phrase.keyword_id)

    %{
      phrase: run_phrase.phrase.phrase,
      niche: run_phrase.niche && run_phrase.niche.name,
      country_volume: run_phrase.volume && run_phrase.volume.search_volume,
      city_volume: run_phrase.city_volume && run_phrase.city_volume.search_volume,
      cpc: run_phrase.volume && run_phrase.volume.cpc,
      currency: run_phrase.volume && run_phrase.volume.currency,
      verdict: reading && reading.verdict,
      holders: reading && Competition.holders(reading.labels),
      current_position: run_phrase.current_position,
      rejected?: run_phrase.status == :rejected,
      rejection_reason: run_phrase.rejection_reason
    }
  end

  defp join_location_volume(query, location_code) do
    join(query, :left, [run_phrase: run_phrase], volume in Volume,
      as: :volume,
      on: volume.keyword_id == run_phrase.keyword_id and volume.location_code == ^location_code
    )
  end

  defp merge_city_volume(query, %Run{city_location_code: nil}) do
    select_merge(query, %{city_volume: nil})
  end

  defp merge_city_volume(query, %Run{city_location_code: city_location_code}) do
    query
    |> join(:left, [run_phrase: run_phrase], city_volume in Volume,
      as: :city_volume,
      on: city_volume.keyword_id == run_phrase.keyword_id and city_volume.location_code == ^city_location_code
    )
    |> select_merge([city_volume: city_volume], %{city_volume: city_volume})
  end

  defp missing_row(phrase, fetched_at) do
    %{
      phrase: phrase,
      search_volume: nil,
      cpc: nil,
      currency: @missing_volume_currency,
      monthly_searches: [],
      fetched_at: fetched_at
    }
  end

  defp distinct_rows_by_phrase(rows) do
    rows
    |> Enum.filter(&is_binary(&1.phrase))
    |> Enum.map(&%{&1 | phrase: Phrase.normalise(&1.phrase)})
    |> Enum.reject(&(&1.phrase == ""))
    |> Enum.uniq_by(& &1.phrase)
    |> Map.new(&{&1.phrase, &1})
  end

  defp upsert_phrases([], _language_code), do: %{}

  defp upsert_phrases(phrases, language_code) do
    now = DateTime.utc_now(:second)

    phrases
    |> Enum.sort()
    |> Enum.map(&%{phrase: &1, language_code: language_code, inserted_at: now, updated_at: now})
    |> insert_in_chunks(Phrase, on_conflict: :nothing, conflict_target: [:phrase, :language_code])

    Phrase
    |> from(as: :phrase)
    |> where([phrase: phrase], phrase.language_code == ^language_code and phrase.phrase in ^phrases)
    |> select([phrase: phrase], {phrase.phrase, phrase.id})
    |> Repo.all()
    |> Map.new()
  end

  defp upsert_volumes(entries, location_code, now) do
    entries
    |> Enum.sort_by(& &1.keyword_id)
    |> Enum.map(fn %{keyword_id: keyword_id, row: row} ->
      %{
        keyword_id: keyword_id,
        location_code: location_code,
        search_volume: row.search_volume,
        cpc: row.cpc,
        currency: row.currency,
        monthly_searches: row.monthly_searches,
        fetched_at: row.fetched_at,
        raw: Map.delete(row, :fetched_at),
        inserted_at: now,
        updated_at: now
      }
    end)
    |> insert_in_chunks(Volume, on_conflict: replace_older_volume(), conflict_target: [:keyword_id, :location_code])
  end

  defp replace_older_volume do
    Volume
    |> from(as: :volume)
    |> where([volume: volume], volume.fetched_at < fragment("EXCLUDED.fetched_at"))
    |> update(
      set: [
        search_volume: fragment("EXCLUDED.search_volume"),
        cpc: fragment("EXCLUDED.cpc"),
        currency: fragment("EXCLUDED.currency"),
        monthly_searches: fragment("EXCLUDED.monthly_searches"),
        fetched_at: fragment("EXCLUDED.fetched_at"),
        raw: fragment("EXCLUDED.raw"),
        updated_at: fragment("EXCLUDED.updated_at")
      ]
    )
  end

  defp link_to_run(%{run: %Run{id: run_id}, phrase_ids: phrase_ids, origin: origin}, now) do
    phrase_ids
    |> Enum.map(&%{run_id: run_id, keyword_id: &1, origin: origin, status: :kept, inserted_at: now, updated_at: now})
    |> insert_in_chunks(RunPhrase, on_conflict: :nothing, conflict_target: [:run_id, :keyword_id])
  end

  defp insert_in_chunks(entries, schema, options) do
    entries
    |> Enum.chunk_every(@insert_chunk_size)
    |> Enum.each(&Repo.insert_all(schema, &1, options))
  end
end
