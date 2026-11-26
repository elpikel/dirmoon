defmodule Dirmoon.PhrasesTest do
  use Dirmoon.DataCase, async: true

  alias Dirmoon.Phrases
  alias Dirmoon.Phrases.Metrics
  alias Dirmoon.Phrases.Phrase
  alias Dirmoon.Phrases.RunPhrase

  test "expansion rows are stored as normalised shared phrases linked to the run" do
    run = insert(:run)
    other_text = unique_phrase_text("hotel dla kota")

    assert {:ok, 2} = Phrases.store_expansion(run, [row("  Hotel   dla PSÓW ", 320), row(other_text, 90)])

    assert Phrase |> Repo.all() |> Enum.map(& &1.phrase) |> Enum.sort() == Enum.sort([other_text, "hotel dla psów"])

    assert [%RunPhrase{status: :kept}, %RunPhrase{status: :kept}] =
             RunPhrase
             |> from(as: :run_phrase)
             |> where([run_phrase: run_phrase], run_phrase.run_id == ^run.id)
             |> Repo.all()
  end

  test "a phrase listed twice in the rows is stored once with the first row's volume" do
    run = insert(:run)
    text = unique_phrase_text("hotel dla psów")

    assert {:ok, 1} = Phrases.store_expansion(run, [row(text, 320), row(String.upcase(text), 10)])

    assert [%Metrics{search_volume: 320}] = Repo.all(Metrics)
    assert Phrases.count_for_run(run) == 1
  end

  test "storing the same rows twice duplicates nothing" do
    run = insert(:run)
    rows = [row(unique_phrase_text("hotel dla psów"), 320), row(unique_phrase_text("hotel dla kota"), 90)]

    {:ok, 2} = Phrases.store_expansion(run, rows)
    assert {:ok, 2} = Phrases.store_expansion(run, rows)

    assert Repo.aggregate(Phrase, :count) == 2
    assert Repo.aggregate(Metrics, :count) == 2
    assert Phrases.count_for_run(run) == 2
  end

  test "a newer fetch replaces older metrics of the phrase for the same location" do
    stored =
      insert(:metrics, location_code: 2616, search_volume: 10, cpc: Decimal.new("0.10"), fetched_at: days_ago(40))

    run = insert(:run, location_code: 2616, language_code: stored.phrase.language_code)
    fetched_at = days_ago(1)

    {:ok, 1} =
      Phrases.store_expansion(run, [
        %{row(stored.phrase.phrase, 500) | cpc: Decimal.new("2.00"), fetched_at: fetched_at}
      ])

    assert [%Metrics{id: metrics_id, search_volume: 500, cpc: cpc, fetched_at: ^fetched_at}] = Repo.all(Metrics)
    assert metrics_id == stored.id
    assert Decimal.equal?(cpc, Decimal.new("2.00"))
  end

  test "an older fetch neither replaces newer metrics nor refreshes its fetch time" do
    newer_fetched_at = days_ago(1)
    stored = insert(:metrics, location_code: 2616, search_volume: 10, fetched_at: newer_fetched_at)
    run = insert(:run, location_code: 2616, language_code: stored.phrase.language_code)

    {:ok, 1} = Phrases.store_expansion(run, [%{row(stored.phrase.phrase, 500) | fetched_at: days_ago(40)}])

    assert [%Metrics{search_volume: 10, fetched_at: ^newer_fetched_at}] = Repo.all(Metrics)
    assert Phrases.count_for_run(run) == 1
  end

  test "shared phrases and metrics hold nothing that identifies the run" do
    run = insert(:run, description: "Opis firmy, który nie może trafić do danych wspólnych")

    {:ok, 1} = Phrases.store_expansion(run, [row(unique_phrase_text("hotel dla psów"), 320)])

    refute :fields |> Phrase.__schema__() |> Enum.concat(Metrics.__schema__(:fields)) |> Enum.member?(:run_id)
    refute inspect(Repo.all(Phrase)) =~ run.description
    refute inspect(Repo.all(Metrics)) =~ run.description
  end

  test "the run's phrases are listed with their country volume, highest volume first and missing volumes last" do
    run = insert(:run, location_code: 2616)
    other_run = insert(:run, location_code: 2616)
    small = unique_phrase_text("mała fraza")
    without_volume = unique_phrase_text("bez wolumenu")
    large = unique_phrase_text("duża fraza")

    {:ok, 3} = Phrases.store_expansion(run, [row(small, 15), row(without_volume, nil), row(large, 900)])

    {:ok, 1} = Phrases.store_expansion(other_run, [row(unique_phrase_text("cudza fraza"), 5000)])

    assert [
             %RunPhrase{phrase: %Phrase{phrase: ^large}, metrics: %Metrics{search_volume: 900, location_code: 2616}},
             %RunPhrase{phrase: %Phrase{phrase: ^small}, metrics: %Metrics{search_volume: 15}},
             %RunPhrase{phrase: %Phrase{phrase: ^without_volume}, metrics: %Metrics{search_volume: nil}}
           ] = Phrases.list_for_run(run)
  end

  test "a phrase with no volume for the run's country is listed without a volume" do
    run_phrase = insert(:run_phrase)
    insert(:metrics, phrase: run_phrase.phrase, location_code: run_phrase.run.location_code + 1)

    assert [%RunPhrase{metrics: nil}] = Phrases.list_for_run(run_phrase.run)
  end

  test "the run's phrases are counted" do
    run = insert(:run)
    insert(:run_phrase, run: run)
    insert(:run_phrase, run: run)
    insert(:run_phrase)

    assert Phrases.count_for_run(run) == 2
  end

  test "a run phrase also lists its city volume when the run has a city location" do
    run = insert(:run, location_code: 2616, city: "Gdańsk", city_location_code: 1_000_123)
    run_phrase = insert(:run_phrase, run: run)
    insert(:metrics, phrase: run_phrase.phrase, location_code: 2616, search_volume: 300)
    insert(:metrics, phrase: run_phrase.phrase, location_code: 1_000_123, search_volume: 30)

    assert [%RunPhrase{metrics: %Metrics{search_volume: 300}, city_metrics: %Metrics{search_volume: 30}}] =
             Phrases.list_for_run(run)
  end

  test "a run phrase has no city volume when the run has no city location" do
    run_phrase = insert(:run_phrase)
    insert(:metrics, phrase: run_phrase.phrase, location_code: run_phrase.run.location_code)

    assert [%RunPhrase{metrics: %Metrics{}, city_metrics: nil}] = Phrases.list_for_run(run_phrase.run)
  end

  test "phrases needing metrics are the run's kept phrases without metrics fetched in the last 30 days" do
    run = insert(:run, location_code: 2616)
    missing = insert(:run_phrase, run: run)
    stale = insert(:run_phrase, run: run)
    fresh = insert(:run_phrase, run: run)
    other_location = insert(:run_phrase, run: run)
    insert(:run_phrase, run: run, status: :rejected)
    insert(:run_phrase)
    insert(:metrics, phrase: stale.phrase, location_code: 2616, fetched_at: days_ago(31))
    insert(:metrics, phrase: fresh.phrase, location_code: 2616, fetched_at: days_ago(29))
    insert(:metrics, phrase: other_location.phrase, location_code: 1_000_123, fetched_at: days_ago(1))

    assert Enum.map(Phrases.phrases_needing_metrics(run, 2616), & &1.id) ==
             [missing.keyword_id, stale.keyword_id, other_location.keyword_id]
  end

  test "stored metrics are matched to the asked phrases by normalised phrase and missing ones are stored empty" do
    returned = insert(:phrase)
    missing = insert(:phrase)
    fetched_at = days_ago(1)

    assert {:ok, 2} =
             Phrases.store_metrics(1_000_123, %{
               phrases: [returned, missing],
               rows: [
                 %{row(" " <> String.upcase(returned.phrase), 40) | fetched_at: fetched_at},
                 row(unique_phrase_text("fraza spoza zapytania"), 9)
               ],
               fetched_at: fetched_at
             })

    assert %Metrics{search_volume: 40, fetched_at: ^fetched_at} =
             Repo.get_by!(Metrics, keyword_id: returned.id, location_code: 1_000_123)

    assert %Metrics{search_volume: nil, cpc: nil, fetched_at: ^fetched_at} =
             Repo.get_by!(Metrics, keyword_id: missing.id, location_code: 1_000_123)

    assert Repo.aggregate(Metrics, :count) == 2
  end

  test "expansion rows store the same phrases and volumes whatever order they arrive in" do
    run = insert(:run, location_code: 2616)
    volumes_by_text = Map.new([30, 10, 20], &{unique_phrase_text("fraza w kolejności"), &1})
    rows = Enum.sort_by(volumes_by_text, fn {_text, search_volume} -> search_volume end, :desc)

    assert {:ok, 3} =
             Phrases.store_expansion(run, Enum.map(rows, fn {text, search_volume} -> row(text, search_volume) end))

    assert stored_volumes_by_text(2616) == volumes_by_text
    assert Phrases.count_for_run(run) == 3
  end

  test "search volume rows store the same volumes whatever order the phrases and rows arrive in" do
    phrases = insert_list(3, :phrase)
    fetched_at = days_ago(1)

    volumes_by_text =
      phrases |> Enum.zip([30, 10, 20]) |> Map.new(fn {phrase, search_volume} -> {phrase.phrase, search_volume} end)

    assert {:ok, 3} =
             Phrases.store_metrics(1_000_123, %{
               phrases: Enum.reverse(phrases),
               rows: Enum.map(Enum.sort(Map.keys(volumes_by_text), :desc), &row(&1, Map.fetch!(volumes_by_text, &1))),
               fetched_at: fetched_at
             })

    assert stored_volumes_by_text(1_000_123) == volumes_by_text
  end

  test "the run's kept phrases are counted" do
    run = insert(:run)
    insert(:run_phrase, run: run)
    insert(:run_phrase, run: run, status: :rejected)

    assert Phrases.count_kept_for_run(run) == 1
  end

  test "phrases assigned to a niche point at it and only the run's own phrases change" do
    run = insert(:run)
    niche = insert(:niche, run: run)
    run_phrase = insert(:run_phrase, run: run)
    other_run_phrase = insert(:run_phrase)

    assert Phrases.assign_to_niche(run, %{niche_id: niche.id, phrase_ids: [run_phrase.id, other_run_phrase.id]}) == 1

    assert Repo.get!(RunPhrase, run_phrase.id).cluster_id == niche.id
    assert Repo.get!(RunPhrase, other_run_phrase.id).cluster_id == nil
  end

  test "rejected phrases get the rejected status and the reason, only in the run" do
    run = insert(:run)
    run_phrase = insert(:run_phrase, run: run)
    other_run_phrase = insert(:run_phrase)

    assert Phrases.reject(run, %{phrase_ids: [run_phrase.id, other_run_phrase.id], reason: "inna branża"}) == 1

    assert %RunPhrase{status: :rejected, rejection_reason: "inna branża"} = Repo.get!(RunPhrase, run_phrase.id)
    assert %RunPhrase{status: :kept, rejection_reason: nil} = Repo.get!(RunPhrase, other_run_phrase.id)
  end

  test "kept phrases without a niche are rejected with the given reason" do
    run = insert(:run)
    niche = insert(:niche, run: run)
    grouped = insert(:run_phrase, run: run, niche: niche)
    ungrouped = insert(:run_phrase, run: run)
    already_rejected = insert(:run_phrase, run: run, status: :rejected, rejection_reason: "inna branża")

    assert Phrases.reject_ungrouped(run, "left out by the model") == 1

    assert Repo.get!(RunPhrase, grouped.id).status == :kept
    assert %RunPhrase{status: :rejected, rejection_reason: "left out by the model"} = Repo.get!(RunPhrase, ungrouped.id)
    assert %RunPhrase{rejection_reason: "inna branża"} = Repo.get!(RunPhrase, already_rejected.id)
  end

  test "clearing the grouping puts every phrase of the run back to kept without a niche" do
    run = insert(:run)
    niche = insert(:niche, run: run)
    grouped = insert(:run_phrase, run: run, niche: niche)
    rejected = insert(:run_phrase, run: run, status: :rejected, rejection_reason: "inna branża")
    other_run_rejected = insert(:run_phrase, status: :rejected, rejection_reason: "inna branża")

    Phrases.clear_grouping(run)

    assert %RunPhrase{status: :kept, cluster_id: nil} = Repo.get!(RunPhrase, grouped.id)
    assert %RunPhrase{status: :kept, rejection_reason: nil} = Repo.get!(RunPhrase, rejected.id)
    assert Repo.get!(RunPhrase, other_run_rejected.id).status == :rejected
  end

  test "current positions are set on the run's phrases matched by normalised text, rounded to one decimal" do
    run = insert(:run)
    phrase = insert(:phrase, phrase: unique_phrase_text("adwokat rozwód"))
    run_phrase = insert(:run_phrase, run: run, phrase: phrase)
    other = insert(:run_phrase, run: run)
    query = "  " <> String.upcase(phrase.phrase) <> "  "

    assert {:ok, %{matched: 1, quick_wins: 1}} =
             Phrases.store_current_positions(run, [%{phrase: query, position: 9.46}])

    assert Decimal.equal?(Repo.get!(RunPhrase, run_phrase.id).current_position, Decimal.new("9.5"))
    assert Repo.get!(RunPhrase, other.id).current_position == nil
  end

  test "only positions from 8 to 20 count as quick wins" do
    run = insert(:run)
    [top, low_edge, high_edge, far] = Enum.map(1..4, fn _index -> insert(:run_phrase, run: run) end)

    rows = [
      %{phrase: top.phrase.phrase, position: 7.9},
      %{phrase: low_edge.phrase.phrase, position: 8},
      %{phrase: high_edge.phrase.phrase, position: 20.0},
      %{phrase: far.phrase.phrase, position: 20.6}
    ]

    assert Phrases.store_current_positions(run, rows) == {:ok, %{matched: 4, quick_wins: 2}}
    assert Phrases.quick_win_range() == 8..20
  end

  test "a Current Position from 8 to 20 makes a Quick Win, and no position makes none" do
    assert Phrases.quick_win?(Decimal.new("8.0"))
    assert Phrases.quick_win?(Decimal.new("20.0"))
    refute Phrases.quick_win?(Decimal.new("7.9"))
    refute Phrases.quick_win?(Decimal.new("20.1"))
    refute Phrases.quick_win?(nil)
  end

  test "a phrase listed twice keeps its best position" do
    run = insert(:run)
    run_phrase = insert(:run_phrase, run: run)
    text = run_phrase.phrase.phrase

    assert {:ok, %{matched: 1}} =
             Phrases.store_current_positions(run, [
               %{phrase: text, position: 14.0},
               %{phrase: String.upcase(text), position: 6.0}
             ])

    assert Decimal.equal?(Repo.get!(RunPhrase, run_phrase.id).current_position, Decimal.new("6.0"))
  end

  test "a phrase listed twice keeps the address of its best position" do
    run = insert(:run)
    run_phrase = insert(:run_phrase, run: run)
    text = run_phrase.phrase.phrase

    assert {:ok, %{matched: 1}} =
             Phrases.store_current_positions(run, [
               %{phrase: text, position: 4, url: "https://strona-testowa.example/lepsza"},
               %{phrase: text, position: 9, url: "https://strona-testowa.example/gorsza"}
             ])

    assert Repo.get!(RunPhrase, run_phrase.id).current_position_url == "https://strona-testowa.example/lepsza"
  end

  test "storing current positions clears a stale address" do
    run = insert(:run)

    stale =
      insert(:run_phrase, run: run, current_position: Decimal.new("12.0"), current_position_url: "https://a.example/")

    assert {:ok, %{matched: 0}} = Phrases.store_current_positions(run, [])

    assert Repo.get!(RunPhrase, stale.id).current_position_url == nil
  end

  test "storing current positions clears the run's stale positions and leaves other runs alone" do
    run = insert(:run)
    stale = insert(:run_phrase, run: run, current_position: Decimal.new("12.0"))
    other_run_phrase = insert(:run_phrase, phrase: stale.phrase, current_position: Decimal.new("15.0"))

    assert Phrases.store_current_positions(run, []) == {:ok, %{matched: 0, quick_wins: 0}}

    assert Repo.get!(RunPhrase, stale.id).current_position == nil
    assert Decimal.equal?(Repo.get!(RunPhrase, other_run_phrase.id).current_position, Decimal.new("15.0"))
  end

  test "market totals sum a niche's kept phrases' country volume and weight their cpc by volume" do
    run = insert(:run)
    niche = insert(:niche, run: run)
    first = phrase_in_niche(run, niche, %{volume: 30, cpc: "1.00"})
    second = phrase_in_niche(run, niche, %{volume: 10, cpc: "3.00"})
    without_cpc = phrase_in_niche(run, niche, %{volume: 20, cpc: nil})
    city_only = phrase_in_niche(run, niche, %{volume: nil, cpc: nil})
    insert(:metrics, phrase: city_only.phrase, location_code: run.location_code + 1, search_volume: 700)

    assert %{volume: 60, cpc: cpc, keyword_ids: keyword_ids} = Map.fetch!(Phrases.market_totals_by_niche(run), niche.id)
    assert Decimal.equal?(cpc, Decimal.new("1.5"))

    assert Enum.sort(keyword_ids) ==
             Enum.sort([first.keyword_id, second.keyword_id, without_cpc.keyword_id, city_only.keyword_id])
  end

  test "a niche's market cpc is the plain average when none of its phrases has a volume" do
    run = insert(:run)
    niche = insert(:niche, run: run)
    phrase_in_niche(run, niche, %{volume: 0, cpc: "1.00"})
    phrase_in_niche(run, niche, %{volume: nil, cpc: "2.00"})

    assert %{volume: 0, cpc: cpc} = Map.fetch!(Phrases.market_totals_by_niche(run), niche.id)
    assert Decimal.equal?(cpc, Decimal.new("1.5"))
  end

  test "a niche's market cpc is nil when none of its phrases has a cpc" do
    run = insert(:run)
    niche = insert(:niche, run: run)
    phrase_in_niche(run, niche, %{volume: 40, cpc: nil})

    assert %{volume: 40, cpc: nil} = Map.fetch!(Phrases.market_totals_by_niche(run), niche.id)
  end

  test "market totals leave out rejected phrases, phrases without a niche and other runs" do
    run = insert(:run)
    niche = insert(:niche, run: run)
    kept = phrase_in_niche(run, niche, %{volume: 25, cpc: "1.00"})
    phrase_in_niche(run, niche, %{volume: 900, cpc: "9.00", status: :rejected})
    phrase_in_niche(run, nil, %{volume: 300, cpc: "4.00"})
    other_run = insert(:run)
    phrase_in_niche(other_run, insert(:niche, run: other_run), %{volume: 70, cpc: "2.00"})

    market_totals = Phrases.market_totals_by_niche(run)

    assert Map.keys(market_totals) == [niche.id]
    assert %{volume: 25, cpc: cpc, keyword_ids: [keyword_id]} = market_totals[niche.id]
    assert keyword_id == kept.keyword_id
    assert Decimal.equal?(cpc, Decimal.new("1"))
  end

  test "a niche without kept phrases has no market totals" do
    run = insert(:run)
    niche = insert(:niche, run: run)
    phrase_in_niche(run, niche, %{volume: 10, cpc: "1.00", status: :rejected})

    assert Phrases.market_totals_by_niche(run) == %{}
  end

  test "the kept Phrases of a run can be listed on their own, at most a given number" do
    run = insert(:run)
    niche = insert(:niche, run: run)
    top = phrase_in_niche(run, niche, %{volume: 300, cpc: nil})
    phrase_in_niche(run, niche, %{volume: 100, cpc: nil})
    phrase_in_niche(run, niche, %{volume: 900, cpc: nil, status: :rejected})

    assert [%RunPhrase{id: top_id, status: :kept}] = Phrases.list_for_run(run, %{status: :kept, limit: 1})
    assert top_id == top.id
  end

  test "the Rejected Phrases of a run can be listed with their reasons" do
    run = insert(:run)
    rejected = insert(:run_phrase, run: run, status: :rejected, rejection_reason: "poza ofertą testową")
    insert(:run_phrase, run: run)

    assert [%RunPhrase{id: rejected_id, rejection_reason: "poza ofertą testową"}] =
             Phrases.list_for_run(run, %{status: :rejected})

    assert rejected_id == rejected.id
  end

  test "a Niche's kept Phrases can be listed without other Niches' Phrases" do
    run = insert(:run)
    niche = insert(:niche, run: run)
    kept = phrase_in_niche(run, niche, %{volume: 40, cpc: nil})
    phrase_in_niche(run, insert(:niche, run: run), %{volume: 80, cpc: nil})

    assert [%RunPhrase{id: kept_id}] = Phrases.list_for_run(run, %{niche_id: niche.id})
    assert kept_id == kept.id
  end

  test "a run's Phrases are counted as kept and rejected" do
    run = insert(:run)
    insert_list(2, :run_phrase, run: run)
    insert(:run_phrase, run: run, status: :rejected, rejection_reason: "poza ofertą")
    insert(:run_phrase)

    assert Phrases.count_by_status(run) == %{kept: 2, rejected: 1}
    assert Phrases.count_by_status(insert(:run)) == %{kept: 0, rejected: 0}
  end

  defp row(phrase, search_volume) do
    %{
      phrase: phrase,
      search_volume: search_volume,
      cpc: Decimal.new("0.40"),
      currency: "USD",
      trend: [],
      fetched_at: DateTime.utc_now(:second)
    }
  end

  defp stored_volumes_by_text(location_code) do
    Metrics
    |> from(as: :metrics)
    |> join(:inner, [metrics: metrics], phrase in assoc(metrics, :phrase), as: :phrase)
    |> where([metrics: metrics], metrics.location_code == ^location_code)
    |> select([metrics: metrics, phrase: phrase], {phrase.phrase, metrics.search_volume})
    |> Repo.all()
    |> Map.new()
  end

  defp phrase_in_niche(run, niche, metrics) do
    phrase = insert(:phrase, phrase: unique_phrase_text("fraza niszy"))

    if metrics.volume || metrics.cpc do
      insert(:metrics,
        phrase: phrase,
        location_code: run.location_code,
        search_volume: metrics.volume,
        cpc: metrics.cpc && Decimal.new(metrics.cpc)
      )
    end

    insert(:run_phrase, run: run, phrase: phrase, niche: niche, status: Map.get(metrics, :status, :kept))
  end

  defp days_ago(days), do: DateTime.shift(DateTime.utc_now(:second), day: -days)
end
