defmodule Dirmoon.Workers.ExpandPhrasesTest do
  use Dirmoon.DataCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  import Mox

  alias Dirmoon.Phrases.Metrics
  alias Dirmoon.Phrases.Phrase
  alias Dirmoon.Phrases.RunPhrase
  alias Dirmoon.Research.ApiRequest
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.RunStep
  alias Dirmoon.Workers.ExpandPhrases
  alias Dirmoon.Workers.FetchVolumes

  test "the phrases the keyword API returned are stored for the run as kept" do
    run = run_with_seeds(seed_list(3))
    texts = Enum.map(["hotel dla psów", "hotel dla kota", "pensjonat dla psa"], &unique_phrase_text/1)
    [dogs, cats, guesthouse] = texts

    expect(Dirmoon.DataForSEOMock, :phrase_ideas, 1, fn _request ->
      ideas([row(dogs, 320), row("  " <> String.upcase(cats) <> " ", 90), row(guesthouse, nil)])
    end)

    assert :ok = perform_job(ExpandPhrases, %{run_id: run.id})

    assert %RunStep{status: :done, result: "3 realne frazy", output: %{"phrases" => 3, "requests" => 1}} =
             step(run, 2)

    run_phrases =
      RunPhrase
      |> from(as: :run_phrase)
      |> where([run_phrase: run_phrase], run_phrase.run_id == ^run.id)
      |> preload(:phrase)
      |> Repo.all()

    assert run_phrases |> Enum.map(& &1.phrase.phrase) |> Enum.sort() == Enum.sort(texts)

    assert Enum.all?(run_phrases, &(&1.status == :kept))
  end

  test "the country volume, cpc and trend of each returned phrase are stored as its metrics" do
    run = run_with_seeds(seed_list(2))
    text = unique_phrase_text("hotel dla psów")

    trend = [
      %{year: 2026, month: 10, search_volume: 300},
      %{year: 2026, month: 9, search_volume: nil}
    ]

    expect(Dirmoon.DataForSEOMock, :phrase_ideas, 1, fn _request ->
      ideas([%{row(text, 320) | cpc: Decimal.new("1.25"), trend: trend}])
    end)

    :ok = perform_job(ExpandPhrases, %{run_id: run.id})

    phrase = Repo.get_by!(Phrase, phrase: text, language_code: "pl")

    assert %Metrics{location_code: 2616, search_volume: 320, currency: "USD", fetched_at: %DateTime{}} =
             metrics = Repo.get_by!(Metrics, keyword_id: phrase.id)

    assert Decimal.equal?(metrics.cpc, Decimal.new("1.25"))

    assert metrics.trend == [
             %{"year" => 2026, "month" => 10, "search_volume" => 300},
             %{"year" => 2026, "month" => 9, "search_volume" => nil}
           ]
  end

  test "thirty-five seeds are sent to the keyword API in batches of at most twenty" do
    seeds = seed_list(35)
    run = run_with_seeds(seeds)
    {first_batch, second_batch} = Enum.split(seeds, 20)

    Dirmoon.DataForSEOMock
    |> expect(:phrase_ideas, 1, fn %{seeds: ^first_batch, location_code: 2616, language_code: "pl"} ->
      ideas([row(unique_phrase_text("pierwsza partia"), 50)])
    end)
    |> expect(:phrase_ideas, 1, fn %{seeds: ^second_batch, location_code: 2616, language_code: "pl"} ->
      ideas([row(unique_phrase_text("druga partia"), 40)])
    end)

    assert :ok = perform_job(ExpandPhrases, %{run_id: run.id})

    assert %RunStep{result: "2 realne frazy", output: %{"requests" => 2}} = step(run, 2)
  end

  test "a phrase another account's run already stored is linked to this run, not duplicated" do
    other_run_phrase = insert(:run_phrase, phrase: build(:phrase, language_code: "pl"))
    text = other_run_phrase.phrase.phrase
    run = run_with_seeds(seed_list(2))

    expect(Dirmoon.DataForSEOMock, :phrase_ideas, 1, fn _request -> ideas([row(" " <> String.upcase(text), 320)]) end)

    :ok = perform_job(ExpandPhrases, %{run_id: run.id})

    assert [%Phrase{id: phrase_id}] =
             Phrase |> from(as: :phrase) |> where([phrase: phrase], phrase.phrase == ^text) |> Repo.all()

    assert phrase_id == other_run_phrase.keyword_id
    assert %RunPhrase{status: :kept} = Repo.get_by!(RunPhrase, run_id: run.id, keyword_id: phrase_id)
    assert Repo.get_by!(RunPhrase, run_id: other_run_phrase.run_id, keyword_id: phrase_id)
  end

  test "each request's cost and raw response are recorded for the run" do
    run = run_with_seeds(seed_list(25))

    Dirmoon.DataForSEOMock
    |> expect(:phrase_ideas, 1, fn _request ->
      ideas([row(unique_phrase_text("pierwsza partia"), 50)], %{
        raw: %{"tasks" => ["pierwsza"]},
        cost: Decimal.new("0.075")
      })
    end)
    |> expect(:phrase_ideas, 1, fn _request ->
      ideas([row(unique_phrase_text("druga partia"), 40)], %{raw: %{"tasks" => ["druga"]}, cost: Decimal.new("0.05")})
    end)

    :ok = perform_job(ExpandPhrases, %{run_id: run.id})

    requests =
      ApiRequest
      |> from(as: :api_request)
      |> where([api_request: api_request], api_request.run_id == ^run.id)
      |> order_by([api_request: api_request], asc: api_request.id)
      |> Repo.all()

    assert [
             %ApiRequest{
               service: "dataforseo",
               operation: "phrase_ideas",
               cost: first_cost,
               response: %{"raw" => %{"tasks" => ["pierwsza"]}}
             },
             %ApiRequest{
               service: "dataforseo",
               operation: "phrase_ideas",
               cost: second_cost,
               response: %{"raw" => %{"tasks" => ["druga"]}}
             }
           ] = requests

    assert Decimal.equal?(first_cost, Decimal.new("0.075"))
    assert Decimal.equal?(second_cost, Decimal.new("0.05"))
  end

  test "decimals in the keyword API's rows and raw answer are stored as decimal strings in every jsonb column" do
    run = run_with_seeds(seed_list(2))
    text = unique_phrase_text("hotel dla psów")
    trend = [%{year: 2026, month: 10, search_volume: 300}]

    expect(Dirmoon.DataForSEOMock, :phrase_ideas, 1, fn _request ->
      ideas([%{row(text, 320) | cpc: Decimal.new("0.66"), trend: trend}], %{
        raw: %{"tasks" => [%{"cost" => Decimal.new("0.075")}]}
      })
    end)

    assert :ok = perform_job(ExpandPhrases, %{run_id: run.id})

    phrase = Repo.get_by!(Phrase, phrase: text, language_code: "pl")
    metrics_row = %{table: "keyword_metrics", where: "keyword_id = $1", value: phrase.id}

    assert [%{"phrase" => ^text, "cpc" => "0.66", "search_volume" => 320, "currency" => "USD"}] =
             stored_json(Map.put(metrics_row, :column, "raw"))

    assert [[%{"year" => 2026, "month" => 10, "search_volume" => 300}]] =
             stored_json(Map.put(metrics_row, :column, "monthly_searches"))

    ledger_row = %{table: "api_requests", where: "run_id = $1", value: run.id}

    assert [%{"rows" => [%{"cpc" => "0.66"}], "raw" => %{"tasks" => [%{"cost" => "0.075"}]}}] =
             stored_json(Map.put(ledger_row, :column, "response"))

    assert [%{"seeds" => _seeds, "location_code" => 2616}] = stored_json(Map.put(ledger_row, :column, "request"))

    assert [%{"phrases" => 1, "requests" => 1}] =
             stored_json(%{table: "run_steps", column: "output", where: "run_id = $1 AND number = 2", value: run.id})
  end

  test "the volumes step is enqueued after the expansion" do
    run = run_with_seeds(seed_list(2))

    expect(Dirmoon.DataForSEOMock, :phrase_ideas, 1, fn _request ->
      ideas([row(unique_phrase_text("hotel dla psów"), 320)])
    end)

    :ok = perform_job(ExpandPhrases, %{run_id: run.id})

    assert_enqueued(worker: FetchVolumes, args: %{run_id: run.id})
  end

  test "running the step again after a reset makes no API call and duplicates nothing" do
    run = run_with_seeds(seed_list(2))

    expect(Dirmoon.DataForSEOMock, :phrase_ideas, 1, fn _request ->
      ideas([row(unique_phrase_text("hotel dla psów"), 320)])
    end)

    :ok = perform_job(ExpandPhrases, %{run_id: run.id})
    run |> step(2) |> RunStep.reset_changeset() |> Repo.update!()

    assert :ok = perform_job(ExpandPhrases, %{run_id: run.id})

    assert %RunStep{status: :done, result: "1 realna fraza"} = step(run, 2)
    assert Repo.aggregate(Phrase, :count) == 1
    assert Repo.aggregate(Metrics, :count) == 1
    assert Repo.aggregate(RunPhrase, :count) == 1
    assert Repo.aggregate(ApiRequest, :count) == 1
  end

  test "replaying a stored batch after a reset keeps the metrics' original fetch time" do
    run = run_with_seeds(seed_list(2))

    expect(Dirmoon.DataForSEOMock, :phrase_ideas, 1, fn _request ->
      ideas([row(unique_phrase_text("hotel dla psów"), 320)])
    end)

    :ok = perform_job(ExpandPhrases, %{run_id: run.id})
    original_fetched_at = DateTime.shift(DateTime.utc_now(:second), day: -40)
    shift_fetch_back_to(run, original_fetched_at)
    run |> step(2) |> RunStep.reset_changeset() |> Repo.update!()

    assert :ok = perform_job(ExpandPhrases, %{run_id: run.id})

    assert [%Metrics{fetched_at: ^original_fetched_at}] = Repo.all(Metrics)
  end

  test "an API error on the second batch keeps the first in the ledger and a retry asks only for the second" do
    seeds = seed_list(35)
    run = run_with_seeds(seeds)
    {first_batch, second_batch} = Enum.split(seeds, 20)

    Dirmoon.DataForSEOMock
    |> expect(:phrase_ideas, 1, fn %{seeds: ^first_batch} -> ideas([row(unique_phrase_text("pierwsza partia"), 50)]) end)
    |> expect(:phrase_ideas, 1, fn %{seeds: ^second_batch} -> {:error, "DataForSEO: Internal Error."} end)

    assert {:error, "DataForSEO: Internal Error."} = perform_job(ExpandPhrases, %{run_id: run.id}, attempt: 1)
    assert [%ApiRequest{request: %{"seeds" => ^first_batch}}] = Repo.all(ApiRequest)
    assert Repo.aggregate(RunPhrase, :count) == 0

    expect(Dirmoon.DataForSEOMock, :phrase_ideas, 1, fn %{seeds: ^second_batch} ->
      ideas([row(unique_phrase_text("druga partia"), 40)])
    end)

    assert :ok = perform_job(ExpandPhrases, %{run_id: run.id}, attempt: 2)

    assert %RunStep{status: :done, result: "2 realne frazy"} = step(run, 2)
    assert Repo.aggregate(ApiRequest, :count) == 2
  end

  test "without DataForSEO credentials the step and the run fail with a readable reason" do
    run = run_with_seeds(seed_list(2))
    expect(Dirmoon.DataForSEOMock, :phrase_ideas, 1, fn _request -> {:error, :data_for_seo_not_configured} end)

    assert {:cancel, :data_for_seo_not_configured} = perform_job(ExpandPhrases, %{run_id: run.id})

    assert %RunStep{status: :failed, error: "Brak danych logowania DataForSEO"} = step(run, 2)
    assert %Run{status: :failed} = Repo.get!(Run, run.id)
    assert all_enqueued() == []
  end

  test "a run without seeds from step 1 fails the step on the last attempt without calling the API" do
    run = insert(:run, steps: build_run_steps(%{1 => :done}, %{1 => %{"seeds" => [], "questions" => []}}))

    assert {:cancel, "Brak fraz startowych z kroku 1"} = perform_job(ExpandPhrases, %{run_id: run.id}, attempt: 3)

    assert %RunStep{status: :failed, error: "Brak fraz startowych z kroku 1"} = step(run, 2)
  end

  test "no phrases for the seeds fail the step on the last attempt" do
    run = run_with_seeds(seed_list(2))
    expect(Dirmoon.DataForSEOMock, :phrase_ideas, 1, fn _request -> ideas([]) end)

    assert {:cancel, "Brak fraz dla tych załążków"} = perform_job(ExpandPhrases, %{run_id: run.id}, attempt: 3)

    assert %RunStep{status: :failed, error: "Brak fraz dla tych załążków"} = step(run, 2)
  end

  defp run_with_seeds(seeds) do
    insert(:run, steps: build_run_steps(%{1 => :done}, %{1 => %{"seeds" => seeds, "questions" => []}}))
  end

  defp seed_list(count), do: Enum.map(1..count, &"fraza startowa #{&1}")

  defp row(phrase, search_volume) do
    %{phrase: phrase, search_volume: search_volume, cpc: Decimal.new("0.40"), currency: "USD", trend: []}
  end

  defp ideas(rows, overrides \\ %{}) do
    {:ok, Map.merge(%{rows: rows, raw: %{"tasks" => []}, cost: Decimal.new("0.075")}, overrides)}
  end

  defp shift_fetch_back_to(run, fetched_at) do
    api_request = Repo.get_by!(ApiRequest, run_id: run.id)

    api_request
    |> Ecto.Changeset.change(response: Map.put(api_request.response, "fetched_at", DateTime.to_iso8601(fetched_at)))
    |> Repo.update!()

    Repo.update_all(Metrics, set: [fetched_at: fetched_at])
  end

  defp step(run, number), do: Repo.get_by!(RunStep, run_id: run.id, number: number)
end
