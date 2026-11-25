defmodule Dirmoon.Workers.FetchVolumesTest do
  use Dirmoon.DataCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  import Mox

  alias Dirmoon.Phrases.Metrics
  alias Dirmoon.Phrases.Phrase
  alias Dirmoon.Research.ApiRequest
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.RunStep
  alias Dirmoon.Workers.FetchVolumes
  alias Dirmoon.Workers.FilterAndGroup

  @city_location_code 1_000_123

  test "with a city that resolves, the city volume and cpc are stored for the run's phrases" do
    run = volumes_run(%{city: "Gdańsk"})
    phrase = kept_phrase(run, "hotel dla psów gdańsk")
    insert(:metrics, phrase: phrase, location_code: run.location_code)

    Dirmoon.DataForSEOMock
    |> expect(:find_location, 1, fn %{city: "Gdańsk", country_code: "PL"} -> city_found() end)
    |> expect(:search_volumes, 1, fn %{phrases: [asked], location_code: @city_location_code} ->
      assert asked == phrase.phrase
      volumes([%{row(String.capitalize(phrase.phrase), 40) | cpc: Decimal.new("1.75")}])
    end)

    assert :ok = perform_job(FetchVolumes, %{run_id: run.id})

    assert %Metrics{search_volume: 40, cpc: cpc} =
             Repo.get_by!(Metrics, keyword_id: phrase.id, location_code: @city_location_code)

    assert Decimal.equal?(cpc, Decimal.new("1.75"))
    assert %Run{city_location_code: @city_location_code} = Repo.get!(Run, run.id)
    assert %RunStep{status: :done, result: "Poland and Gdańsk, 12-month trend"} = step(run, 3)
  end

  test "decimals in the city volume rows and raw answer are stored as decimal strings in every jsonb column" do
    run = volumes_run(%{city: "Gdańsk"})
    phrase = kept_phrase(run, "hotel dla psów gdańsk")
    insert(:metrics, phrase: phrase, location_code: run.location_code)

    Dirmoon.DataForSEOMock
    |> expect(:find_location, 1, fn _request -> city_found() end)
    |> expect(:search_volumes, 1, fn _request ->
      volumes([%{row(phrase.phrase, 40) | cpc: Decimal.new("0.66")}], %{
        raw: %{"tasks" => [%{"cost" => Decimal.new("0.075")}]}
      })
    end)

    assert :ok = perform_job(FetchVolumes, %{run_id: run.id})

    assert [%{"cpc" => "0.66", "search_volume" => 40}] =
             stored_json(%{
               table: "keyword_metrics",
               column: "raw",
               where: "location_code = #{@city_location_code} AND keyword_id = $1",
               value: phrase.id
             })

    assert [%{"location_code" => @city_location_code}, %{"rows" => [%{"cpc" => "0.66"}], "raw" => raw}] =
             stored_json(%{table: "api_requests", column: "response", where: "run_id = $1", value: run.id})

    assert raw == %{"tasks" => [%{"cost" => "0.075"}]}

    assert [%{"city_location_code" => @city_location_code, "country" => _country, "city" => _city}] =
             stored_json(%{table: "run_steps", column: "output", where: "run_id = $1 AND number = 3", value: run.id})
  end

  test "a phrase whose metrics for the location were fetched less than 30 days ago is not requested again" do
    run = volumes_run()
    fresh_phrase = kept_phrase(run, "świeża fraza")
    stale_phrase = kept_phrase(run, "nieznana fraza")
    insert(:metrics, phrase: fresh_phrase, location_code: run.location_code, fetched_at: days_ago(29))

    expect(Dirmoon.DataForSEOMock, :search_volumes, 1, fn %{phrases: [asked], location_code: 2616} ->
      assert asked == stale_phrase.phrase
      volumes([row(asked, 70)])
    end)

    assert :ok = perform_job(FetchVolumes, %{run_id: run.id})

    assert %Metrics{search_volume: 70} = Repo.get_by!(Metrics, keyword_id: stale_phrase.id)

    assert %RunStep{status: :done, output: %{"country" => %{"requested" => 1, "reused" => 1}}} = step(run, 3)
  end

  test "metrics another account's run fetched recently are reused" do
    run = volumes_run()
    other_run = insert(:run)
    phrase = kept_phrase(run, "wspólna fraza")
    insert(:run_phrase, run: other_run, phrase: phrase)
    insert(:metrics, phrase: phrase, location_code: run.location_code, fetched_at: days_ago(3))

    assert :ok = perform_job(FetchVolumes, %{run_id: run.id})

    assert %RunStep{status: :done} = step(run, 3)
  end

  test "metrics fetched more than 30 days ago are requested again and replaced" do
    run = volumes_run()
    phrase = kept_phrase(run, "stara fraza")
    insert(:metrics, phrase: phrase, location_code: run.location_code, search_volume: 5, fetched_at: days_ago(31))

    expect(Dirmoon.DataForSEOMock, :search_volumes, 1, fn %{phrases: [asked]} ->
      assert asked == phrase.phrase
      volumes([row(asked, 120)])
    end)

    assert :ok = perform_job(FetchVolumes, %{run_id: run.id})

    assert [%Metrics{search_volume: 120}] = Repo.all(Metrics)
  end

  test "a city that doesn't resolve finishes the step with the country volume and makes no city request" do
    run = volumes_run(%{city: "Nibylandia"})
    phrase = kept_phrase(run, "hotel dla psów")
    insert(:metrics, phrase: phrase, location_code: run.location_code)

    expect(Dirmoon.DataForSEOMock, :find_location, 1, fn _request -> {:error, :not_found} end)

    assert :ok = perform_job(FetchVolumes, %{run_id: run.id})

    assert %RunStep{status: :done, result: "No data for the city, using the country volume"} = step(run, 3)
    assert %Run{city_location_code: nil} = Repo.get!(Run, run.id)
  end

  test "a failed city lookup fails the attempt, records nothing and asks for no volumes" do
    run = volumes_run(%{city: "Gdańsk"})
    kept_phrase(run, "hotel dla psów")

    Dirmoon.DataForSEOMock
    |> expect(:find_location, 1, fn _request -> {:error, "DataForSEO: Internal Error."} end)
    |> expect(:search_volumes, 0, fn _request -> flunk("no volumes before the city is resolved") end)

    assert {:error, "DataForSEO: Internal Error."} = perform_job(FetchVolumes, %{run_id: run.id}, attempt: 1)

    assert Repo.all_by(ApiRequest, run_id: run.id) == []
    assert %Run{city_location_code: nil} = Repo.get!(Run, run.id)
    assert %RunStep{status: :running} = step(run, 3)
  end

  test "a city that didn't resolve is not looked up again when the step runs again" do
    run = volumes_run(%{city: "Nibylandia"})
    expect(Dirmoon.DataForSEOMock, :find_location, 1, fn _request -> {:error, :not_found} end)

    :ok = perform_job(FetchVolumes, %{run_id: run.id})
    run |> step(3) |> RunStep.reset_changeset() |> Repo.update!()

    assert :ok = perform_job(FetchVolumes, %{run_id: run.id})

    assert %RunStep{status: :done, result: "No data for the city, using the country volume"} = step(run, 3)
  end

  test "a run without a city whose country volumes are all stored finishes without an API call" do
    run = volumes_run()
    insert(:metrics, phrase: kept_phrase(run, "hotel dla psów"), location_code: run.location_code)
    insert(:metrics, phrase: kept_phrase(run, "hotel dla kota"), location_code: run.location_code)

    assert :ok = perform_job(FetchVolumes, %{run_id: run.id})

    assert %RunStep{
             status: :done,
             result: "Poland, 12-month trend",
             output: %{"country" => %{"requested" => 0, "reused" => 2}, "city" => nil}
           } = step(run, 3)

    assert Repo.aggregate(ApiRequest, :count) == 0
  end

  test "more than a thousand phrases are requested in batches of at most a thousand" do
    run = volumes_run()
    prefix = unique_phrase_text("fraza numer")
    phrases = Enum.map(1..1001, &"#{prefix} #{String.pad_leading(Integer.to_string(&1), 4, "0")}")
    link_phrases(run, phrases)
    {first_batch, second_batch} = Enum.split(phrases, 1000)

    Dirmoon.DataForSEOMock
    |> expect(:search_volumes, 1, fn %{phrases: ^first_batch} -> volumes([]) end)
    |> expect(:search_volumes, 1, fn %{phrases: ^second_batch} -> volumes([]) end)

    assert :ok = perform_job(FetchVolumes, %{run_id: run.id})

    assert Repo.aggregate(Metrics, :count) == 1001
  end

  test "phrases the API returns without being asked are ignored" do
    run = volumes_run()
    phrase = kept_phrase(run, "hotel dla psów")
    unasked_text = unique_phrase_text("fraza spoza zapytania")

    expect(Dirmoon.DataForSEOMock, :search_volumes, 1, fn _request ->
      volumes([row(phrase.phrase, 80), row(unasked_text, 999)])
    end)

    assert :ok = perform_job(FetchVolumes, %{run_id: run.id})

    assert [%Metrics{search_volume: 80}] = Repo.all(Metrics)
    refute Repo.get_by(Phrase, phrase: unasked_text)
  end

  test "returned rows are matched to the asked phrases by phrase, not by position" do
    run = volumes_run()
    first = kept_phrase(run, "pierwsza fraza")
    second = kept_phrase(run, "druga fraza")

    expect(Dirmoon.DataForSEOMock, :search_volumes, 1, fn _request ->
      volumes([second.phrase |> String.replace(" ", "  ") |> String.capitalize() |> row(20), row(first.phrase, 10)])
    end)

    assert :ok = perform_job(FetchVolumes, %{run_id: run.id})

    assert %Metrics{search_volume: 10} = Repo.get_by!(Metrics, keyword_id: first.id)
    assert %Metrics{search_volume: 20} = Repo.get_by!(Metrics, keyword_id: second.id)
  end

  test "a phrase asked but not returned gets empty metrics and is not requested again" do
    run = volumes_run()
    phrase = kept_phrase(run, "fraza bez danych")
    expect(Dirmoon.DataForSEOMock, :search_volumes, 1, fn _request -> volumes([]) end)

    :ok = perform_job(FetchVolumes, %{run_id: run.id})

    assert %Metrics{search_volume: nil, cpc: nil, fetched_at: %DateTime{}} = Repo.get_by!(Metrics, keyword_id: phrase.id)

    other_run = volumes_run()
    insert(:run_phrase, run: other_run, phrase: phrase)

    assert :ok = perform_job(FetchVolumes, %{run_id: other_run.id})
    assert %RunStep{status: :done} = step(other_run, 3)
  end

  test "rejected phrases are not requested" do
    run = volumes_run()
    kept = kept_phrase(run, "zachowana fraza")
    insert(:run_phrase, run: run, status: :rejected)

    expect(Dirmoon.DataForSEOMock, :search_volumes, 1, fn %{phrases: [asked]} ->
      assert asked == kept.phrase
      volumes([row(asked, 30)])
    end)

    assert :ok = perform_job(FetchVolumes, %{run_id: run.id})
  end

  test "each request is recorded in the run's ledger with its cost" do
    run = volumes_run(%{city: "Gdańsk"})
    kept_phrase(run, "hotel dla psów")

    Dirmoon.DataForSEOMock
    |> expect(:find_location, 1, fn _request -> city_found() end)
    |> expect(:search_volumes, 2, fn %{phrases: phrases} ->
      volumes(Enum.map(phrases, &row(&1, 10)), %{cost: Decimal.new("0.075")})
    end)

    :ok = perform_job(FetchVolumes, %{run_id: run.id})

    assert ApiRequest
           |> from(as: :api_request)
           |> where([api_request: api_request], api_request.run_id == ^run.id)
           |> select([api_request: api_request], api_request.operation)
           |> Repo.all()
           |> Enum.sort() ==
             ["find_location", "search_volumes", "search_volumes"]

    assert %ApiRequest{response: %{"location_code" => @city_location_code}} =
             Repo.get_by!(ApiRequest, run_id: run.id, operation: "find_location")
  end

  test "the filter and group step is enqueued after the volumes" do
    run = volumes_run()

    :ok = perform_job(FetchVolumes, %{run_id: run.id})

    assert_enqueued(worker: FilterAndGroup, args: %{run_id: run.id})
  end

  test "running the step again after a reset makes no second API call" do
    run = volumes_run(%{city: "Gdańsk"})
    kept_phrase(run, "hotel dla psów")

    Dirmoon.DataForSEOMock
    |> expect(:find_location, 1, fn _request -> city_found() end)
    |> expect(:search_volumes, 2, fn %{phrases: phrases} -> volumes(Enum.map(phrases, &row(&1, 10))) end)

    :ok = perform_job(FetchVolumes, %{run_id: run.id})
    run |> step(3) |> RunStep.reset_changeset() |> Repo.update!()

    assert :ok = perform_job(FetchVolumes, %{run_id: run.id})

    assert %RunStep{status: :done, result: "Poland and Gdańsk, 12-month trend"} = step(run, 3)
    assert Repo.aggregate(ApiRequest, :count) == 3
  end

  test "an API error fails the attempt and a retry asks only for what is still missing" do
    run = volumes_run()
    phrase = kept_phrase(run, "hotel dla psów")

    expect(Dirmoon.DataForSEOMock, :search_volumes, 1, fn _request -> {:error, "DataForSEO: Internal Error."} end)

    assert {:error, "DataForSEO: Internal Error."} = perform_job(FetchVolumes, %{run_id: run.id}, attempt: 1)
    assert Repo.aggregate(ApiRequest, :count) == 0

    expect(Dirmoon.DataForSEOMock, :search_volumes, 1, fn _request -> volumes([row(phrase.phrase, 10)]) end)

    assert :ok = perform_job(FetchVolumes, %{run_id: run.id}, attempt: 2)
    assert %RunStep{status: :done} = step(run, 3)
  end

  defp volumes_run(attrs \\ %{}) do
    insert(:run, Map.merge(%{steps: build_run_steps(%{1 => :done, 2 => :done})}, attrs))
  end

  defp kept_phrase(run, text) do
    phrase = insert(:phrase, phrase: unique_phrase_text(text), language_code: run.language_code)
    insert(:run_phrase, run: run, phrase: phrase)
    phrase
  end

  defp link_phrases(run, texts) do
    now = DateTime.utc_now(:second)

    {_count, phrases} =
      Repo.insert_all(
        Phrase,
        Enum.map(texts, &%{phrase: &1, language_code: run.language_code, inserted_at: now, updated_at: now}),
        returning: [:id]
      )

    Repo.insert_all(
      Dirmoon.Phrases.RunPhrase,
      Enum.map(
        phrases,
        &%{run_id: run.id, keyword_id: &1.id, status: :kept, inserted_at: now, updated_at: now}
      )
    )
  end

  defp city_found do
    {:ok,
     %{location_code: @city_location_code, name: "Gdansk,Pomeranian Voivodeship,Poland", raw: %{}, cost: Decimal.new("0")}}
  end

  defp row(phrase, search_volume) do
    %{phrase: phrase, search_volume: search_volume, cpc: Decimal.new("0.40"), currency: "USD", trend: []}
  end

  defp volumes(rows, overrides \\ %{}) do
    {:ok, Map.merge(%{rows: rows, raw: %{"tasks" => []}, cost: Decimal.new("0.075")}, overrides)}
  end

  defp days_ago(days), do: DateTime.shift(DateTime.utc_now(:second), day: -days)

  defp step(run, number), do: Repo.get_by!(RunStep, run_id: run.id, number: number)
end
