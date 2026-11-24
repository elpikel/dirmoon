defmodule Dirmoon.Workers.CheckCompetitionTest do
  use Dirmoon.DataCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  import Mox

  alias Dirmoon.Competition.SerpAssessment
  alias Dirmoon.Competition.SerpSnapshot
  alias Dirmoon.Phrases.RunPhrase
  alias Dirmoon.Research
  alias Dirmoon.Research.ApiRequest
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.RunStep
  alias Dirmoon.Workers.CheckCompetition

  test "the top 10 is fetched for the kept phrases with the highest country volume, up to the configured limit" do
    run = insert(:run, steps: build_run_steps())
    niche = insert(:niche, run: run)
    limit = Application.fetch_env!(:dirmoon, :serp_phrase_limit)
    checked = Enum.map(1..limit, &phrase_in_niche(run, niche, "fraza sprawdzana", 1000 - &1))
    without_volume = phrase_in_niche_without_volume(run, niche, "fraza bez wolumenu")
    test_process = self()

    expect(Dirmoon.DataForSEOMock, :serp_top10, limit, fn request ->
      send(test_process, {:serp_request, request})
      serp_answer([])
    end)

    assert :ok = perform_job(CheckCompetition, %{run_id: run.id})

    requested = received_serp_requests()

    assert Enum.map(requested, & &1.phrase) == Enum.map(checked, & &1.phrase.phrase)
    assert Enum.all?(requested, &(&1.location_code == run.location_code and &1.language_code == run.language_code))
    refute Repo.get_by(SerpAssessment, run_id: run.id, keyword_id: without_volume.keyword_id)
  end

  test "rejected phrases and phrases outside a niche are not checked" do
    run = insert(:run, steps: build_run_steps())
    niche = insert(:niche, run: run)
    checked = phrase_in_niche(run, niche, "hotel dla psów", 100)
    rejected = phrase_in_niche(run, niche, "hotel w zakopanem", 900)

    RunPhrase
    |> from(as: :run_phrase)
    |> where([run_phrase: run_phrase], run_phrase.id == ^rejected.id)
    |> Repo.update_all(set: [status: :rejected])

    ungrouped = insert(:run_phrase, run: run, phrase: insert(:phrase, phrase: unique_phrase_text("psi hotel")))
    test_process = self()

    expect(Dirmoon.DataForSEOMock, :serp_top10, 1, fn request ->
      send(test_process, {:serp_request, request.phrase})
      serp_answer([])
    end)

    :ok = perform_job(CheckCompetition, %{run_id: run.id})

    assert_received {:serp_request, phrase}
    assert phrase == checked.phrase.phrase
    refute Repo.get_by(SerpAssessment, run_id: run.id, keyword_id: rejected.keyword_id)
    refute Repo.get_by(SerpAssessment, run_id: run.id, keyword_id: ungrouped.keyword_id)
  end

  test "a snapshot fetched less than 30 days ago is reused without a SERP request" do
    run = insert(:run, steps: build_run_steps())
    run_phrase = phrase_in_niche(run, insert(:niche, run: run), "hotel dla psów", 100)

    snapshot =
      insert(:serp_snapshot,
        phrase: run_phrase.phrase,
        location_code: run.location_code,
        fetched_at: DateTime.shift(DateTime.utc_now(:second), day: -29)
      )

    expect(Dirmoon.DataForSEOMock, :serp_top10, 0, fn _request -> serp_answer([]) end)
    expect(Dirmoon.LLMMock, :structured, 1, &label_all(&1, "blog"))

    :ok = perform_job(CheckCompetition, %{run_id: run.id})

    assert %SerpAssessment{serp_snapshot_id: snapshot_id, reused_snapshot: true} =
             Repo.get_by(SerpAssessment, run_id: run.id, keyword_id: run_phrase.keyword_id)

    assert snapshot_id == snapshot.id
    assert %RunStep{output: %{"reused_snapshots" => 1}} = step(run, 5)
    refute Repo.get_by(ApiRequest, run_id: run.id, operation: "serp_top10")
  end

  test "a snapshot older than 30 days is fetched again and stored as a new snapshot" do
    run = insert(:run, steps: build_run_steps())
    run_phrase = phrase_in_niche(run, insert(:niche, run: run), "hotel dla psów", 100)

    old_snapshot =
      insert(:serp_snapshot,
        phrase: run_phrase.phrase,
        location_code: run.location_code,
        fetched_at: DateTime.shift(DateTime.utc_now(:second), day: -31)
      )

    expect(Dirmoon.DataForSEOMock, :serp_top10, 1, fn _request -> serp_answer(serp_rows(["nowy-wynik.example"])) end)
    expect(Dirmoon.LLMMock, :structured, 1, &label_all(&1, "blog"))

    :ok = perform_job(CheckCompetition, %{run_id: run.id})

    assert %SerpAssessment{serp_snapshot_id: snapshot_id, reused_snapshot: false} =
             Repo.get_by(SerpAssessment, run_id: run.id, keyword_id: run_phrase.keyword_id)

    refute snapshot_id == old_snapshot.id
    assert %SerpSnapshot{results: [%{"domain" => "nowy-wynik.example"}]} = Repo.get!(SerpSnapshot, snapshot_id)
  end

  test "another account's fresh snapshot is reused but the run asks for its own labels" do
    run = insert(:run, steps: build_run_steps())
    run_phrase = phrase_in_niche(run, insert(:niche, run: run), "hotel dla psów", 100)
    snapshot = insert(:serp_snapshot, phrase: run_phrase.phrase, location_code: run.location_code)
    other_run = insert(:run)

    other_assessment =
      insert(:serp_assessment, run: other_run, phrase: run_phrase.phrase, serp_snapshot: snapshot, verdict: :weak)

    expect(Dirmoon.LLMMock, :structured, 1, &label_all(&1, "direct_competitor"))

    :ok = perform_job(CheckCompetition, %{run_id: run.id})

    assert %SerpAssessment{serp_snapshot_id: snapshot_id, verdict: :strong} =
             Repo.get_by(SerpAssessment, run_id: run.id, keyword_id: run_phrase.keyword_id)

    assert snapshot_id == snapshot.id
    assert Repo.reload!(other_assessment).labels == other_assessment.labels
  end

  test "each result gets one page type, stored for the run and not in the shared snapshot" do
    run = insert(:run, steps: build_run_steps())
    run_phrase = phrase_in_niche(run, insert(:niche, run: run), "hotel dla psów", 100)
    rows = serp_rows(["psi-hotel.example", "katalog.example", "forum.example"])

    expect(Dirmoon.DataForSEOMock, :serp_top10, 1, fn _request -> serp_answer(rows) end)

    expect(Dirmoon.LLMMock, :structured, 1, fn %{task: :label_serp} ->
      label_answer([
        %{"position" => 3, "page_type" => "forum"},
        %{"position" => 1, "page_type" => "direct_competitor"},
        %{"position" => 2, "page_type" => "directory"}
      ])
    end)

    :ok = perform_job(CheckCompetition, %{run_id: run.id})

    assert %SerpAssessment{labels: labels, serp_snapshot_id: snapshot_id} =
             Repo.get_by(SerpAssessment, run_id: run.id, keyword_id: run_phrase.keyword_id)

    assert labels == [
             %{"position" => 1, "page_type" => "direct_competitor"},
             %{"position" => 2, "page_type" => "directory"},
             %{"position" => 3, "page_type" => "forum"}
           ]

    assert %SerpSnapshot{results: results, keyword_id: keyword_id, location_code: location_code} =
             Repo.get!(SerpSnapshot, snapshot_id)

    assert keyword_id == run_phrase.keyword_id
    assert location_code == run.location_code

    assert results == [
             %{
               "position" => 1,
               "url" => "https://psi-hotel.example/",
               "domain" => "psi-hotel.example",
               "title" => "Wynik 1"
             },
             %{"position" => 2, "url" => "https://katalog.example/", "domain" => "katalog.example", "title" => "Wynik 2"},
             %{"position" => 3, "url" => "https://forum.example/", "domain" => "forum.example", "title" => "Wynik 3"}
           ]
  end

  test "labels for positions outside the top 10, unknown page types and repeated positions are ignored" do
    run = insert(:run, steps: build_run_steps())
    run_phrase = phrase_in_niche(run, insert(:niche, run: run), "hotel dla psów", 100)

    expect(Dirmoon.DataForSEOMock, :serp_top10, 1, fn _request ->
      serp_answer(serp_rows(["blog.example", "forum.example"]))
    end)

    expect(Dirmoon.LLMMock, :structured, 1, fn _request ->
      label_answer([
        %{"position" => 1, "page_type" => "blog"},
        %{"position" => 1, "page_type" => "portal"},
        %{"position" => 2, "page_type" => "sklep"},
        %{"position" => 2, "page_type" => "forum"},
        %{"position" => 11, "page_type" => "portal"}
      ])
    end)

    :ok = perform_job(CheckCompetition, %{run_id: run.id})

    assert %SerpAssessment{labels: labels} =
             Repo.get_by(SerpAssessment, run_id: run.id, keyword_id: run_phrase.keyword_id)

    assert labels == [%{"position" => 1, "page_type" => "blog"}, %{"position" => 2, "page_type" => "forum"}]
  end

  test "an answer that doesn't label every result is not stored and the step is retried" do
    run = insert(:run, steps: build_run_steps())
    run_phrase = phrase_in_niche(run, insert(:niche, run: run), "hotel dla psów", 100)

    expect(Dirmoon.DataForSEOMock, :serp_top10, 1, fn _request ->
      serp_answer(serp_rows(["blog.example", "forum.example"]))
    end)

    expect(Dirmoon.LLMMock, :structured, 1, fn _request ->
      label_answer([%{"position" => 1, "page_type" => "blog"}])
    end)

    assert {:error, "Model nie oznaczył wszystkich wyników"} = perform_job(CheckCompetition, %{run_id: run.id})

    refute Repo.get_by(ApiRequest, run_id: run.id, operation: "label_serp")
    refute Repo.get_by(SerpAssessment, run_id: run.id, keyword_id: run_phrase.keyword_id)
  end

  test "an empty top 10 is assessed as weak without asking the model" do
    run = insert(:run, steps: build_run_steps())
    run_phrase = phrase_in_niche(run, insert(:niche, run: run), "hotel dla psów", 100)

    expect(Dirmoon.DataForSEOMock, :serp_top10, 1, fn _request -> serp_answer([]) end)
    expect(Dirmoon.LLMMock, :structured, 0, fn _request -> label_answer([]) end)

    :ok = perform_job(CheckCompetition, %{run_id: run.id})

    assert %SerpAssessment{labels: [], verdict: :weak} =
             Repo.get_by(SerpAssessment, run_id: run.id, keyword_id: run_phrase.keyword_id)
  end

  test "each phrase's verdict is stored and the step is done with the counts" do
    run = insert(:run, steps: build_run_steps())
    niche = insert(:niche, run: run)
    weak = phrase_in_niche(run, niche, "hotel dla psów", 300)
    strong = phrase_in_niche(run, niche, "hotel dla psa cena", 200)
    medium = phrase_in_niche(run, niche, "psi hotel opinie", 100)
    page_types = %{weak.phrase.phrase => "forum", strong.phrase.phrase => "direct_competitor"}

    stub(Dirmoon.DataForSEOMock, :serp_top10, fn _request ->
      serp_answer(serp_rows(Enum.map(1..10, &"wynik-#{&1}.example")))
    end)

    stub(Dirmoon.LLMMock, :structured, fn %{input: %{phrase: phrase}} = request ->
      label_all(request, Map.get(page_types, phrase, "portal"))
    end)

    assert :ok = perform_job(CheckCompetition, %{run_id: run.id})

    assert verdict(run, weak) == :weak
    assert verdict(run, strong) == :strong
    assert verdict(run, medium) == :medium

    assert %RunStep{status: :done, result: "3 z 3 fraz sprawdzonych", output: output} = step(run, 5)

    assert output == %{
             "checked" => 3,
             "total" => 3,
             "reused_snapshots" => 0,
             "weak" => 1,
             "medium" => 1,
             "strong" => 1
           }
  end

  test "subscribers are told after each phrase how many are checked and who holds its top 10" do
    run = insert(:run, steps: build_run_steps())
    niche = insert(:niche, run: run)
    first = phrase_in_niche(run, niche, "hotel dla psów", 300)
    second = phrase_in_niche(run, niche, "hotel dla psa cena", 200)
    Research.subscribe(run)

    stub(Dirmoon.DataForSEOMock, :serp_top10, fn _request ->
      serp_answer(serp_rows(Enum.map(1..10, &"wynik-#{&1}.example")))
    end)

    stub(Dirmoon.LLMMock, :structured, fn %{input: %{results: results}} ->
      results
      |> Enum.map(&%{"position" => &1.position, "page_type" => page_type_at(&1.position)})
      |> label_answer()
    end)

    :ok = perform_job(CheckCompetition, %{run_id: run.id})

    run_id = run.id
    first_text = first.phrase.phrase
    first_keyword_id = first.keyword_id
    second_text = second.phrase.phrase
    second_keyword_id = second.keyword_id

    assert_received {:run_progress, ^run_id,
                     %{
                       step: 5,
                       checked: 1,
                       total: 2,
                       phrase: ^first_text,
                       keyword_id: ^first_keyword_id,
                       holders: "blogi, fora",
                       verdict: :weak
                     }}

    assert_received {:run_progress, ^run_id,
                     %{
                       step: 5,
                       checked: 2,
                       total: 2,
                       phrase: ^second_text,
                       keyword_id: ^second_keyword_id,
                       holders: "blogi, fora",
                       verdict: :weak
                     }}
  end

  test "the prompt carries the business, the mode with the site's domain and the ten results" do
    run =
      insert(:run,
        description: "Hotel dla psów pod miastem",
        mode: :existing_site,
        domain: "psi-hotel.example",
        steps: build_run_steps()
      )

    run_phrase = phrase_in_niche(run, insert(:niche, run: run), "hotel dla psów", 100)
    test_process = self()

    expect(Dirmoon.DataForSEOMock, :serp_top10, 1, fn _request -> serp_answer(serp_rows(["katalog.example"])) end)

    expect(Dirmoon.LLMMock, :structured, 1, fn request ->
      send(test_process, {:llm_request, request})
      label_all(request, "directory")
    end)

    :ok = perform_job(CheckCompetition, %{run_id: run.id})

    assert_received {:llm_request, %{task: :label_serp, prompt: prompt, input: input}}
    assert prompt =~ "Hotel dla psów pod miastem"
    assert prompt =~ "psi-hotel.example"
    assert prompt =~ "1. katalog.example: Wynik 1 (https://katalog.example/)"

    assert input == %{
             phrase: run_phrase.phrase.phrase,
             results: [%{position: 1, url: "https://katalog.example/", domain: "katalog.example", title: "Wynik 1"}]
           }
  end

  test "a retry after an error on the third phrase doesn't check the first two again" do
    run = insert(:run, steps: build_run_steps())
    niche = insert(:niche, run: run)
    phrase_in_niche(run, niche, "hotel dla psów", 300)
    phrase_in_niche(run, niche, "hotel dla psa cena", 200)
    third = phrase_in_niche(run, niche, "psi hotel opinie", 100)
    third_text = third.phrase.phrase
    rows = serp_rows(["blog.example"])

    expect(Dirmoon.DataForSEOMock, :serp_top10, 3, fn
      %{phrase: ^third_text} -> {:error, "DataForSEO: Internal Error"}
      _request -> serp_answer(rows)
    end)

    expect(Dirmoon.LLMMock, :structured, 2, &label_all(&1, "blog"))

    assert {:error, "DataForSEO: Internal Error"} = perform_job(CheckCompetition, %{run_id: run.id})

    assert SerpAssessment
           |> from(as: :serp_assessment)
           |> where([serp_assessment: serp_assessment], serp_assessment.run_id == ^run.id)
           |> Repo.aggregate(:count) == 2

    expect(Dirmoon.DataForSEOMock, :serp_top10, 1, fn %{phrase: ^third_text} -> serp_answer(rows) end)
    expect(Dirmoon.LLMMock, :structured, 1, &label_all(&1, "blog"))

    assert :ok = perform_job(CheckCompetition, %{run_id: run.id}, attempt: 2)
    assert %RunStep{status: :done, result: "3 z 3 fraz sprawdzonych"} = step(run, 5)
  end

  test "a retry after the model failed labels the top 10 the run bought, not counting it as reused" do
    run = insert(:run, steps: build_run_steps())
    run_phrase = phrase_in_niche(run, insert(:niche, run: run), "hotel dla psów", 100)

    expect(Dirmoon.DataForSEOMock, :serp_top10, 1, fn _request -> serp_answer(serp_rows(["blog.example"])) end)
    expect(Dirmoon.LLMMock, :structured, 1, fn _request -> {:error, "LLM: timeout"} end)

    assert {:error, "LLM: timeout"} = perform_job(CheckCompetition, %{run_id: run.id})

    expect(Dirmoon.LLMMock, :structured, 1, &label_all(&1, "blog"))

    assert :ok = perform_job(CheckCompetition, %{run_id: run.id}, attempt: 2)

    assert [%SerpSnapshot{id: snapshot_id}] =
             SerpSnapshot
             |> from(as: :serp_snapshot)
             |> where([serp_snapshot: serp_snapshot], serp_snapshot.keyword_id == ^run_phrase.keyword_id)
             |> Repo.all()

    assert %SerpAssessment{serp_snapshot_id: ^snapshot_id, reused_snapshot: false} =
             Repo.get_by(SerpAssessment, run_id: run.id, keyword_id: run_phrase.keyword_id)

    assert %RunStep{output: %{"reused_snapshots" => 0}} = step(run, 5)
  end

  test "a top 10 the run bought is replayed from its ledger after it expired without storing a second snapshot" do
    run = insert(:run, steps: build_run_steps())
    run_phrase = phrase_in_niche(run, insert(:niche, run: run), "hotel dla psów", 100)

    expect(Dirmoon.DataForSEOMock, :serp_top10, 1, fn _request -> serp_answer(serp_rows(["blog.example"])) end)
    expect(Dirmoon.LLMMock, :structured, 1, fn _request -> {:error, "LLM: timeout"} end)

    assert {:error, "LLM: timeout"} = perform_job(CheckCompetition, %{run_id: run.id})

    age_bought_top10(run, 31)
    expect(Dirmoon.LLMMock, :structured, 1, &label_all(&1, "blog"))

    assert :ok = perform_job(CheckCompetition, %{run_id: run.id}, attempt: 2)

    assert [%SerpSnapshot{id: snapshot_id}] =
             SerpSnapshot
             |> from(as: :serp_snapshot)
             |> where([serp_snapshot: serp_snapshot], serp_snapshot.keyword_id == ^run_phrase.keyword_id)
             |> Repo.all()

    assert %SerpAssessment{serp_snapshot_id: ^snapshot_id, reused_snapshot: false} =
             Repo.get_by(SerpAssessment, run_id: run.id, keyword_id: run_phrase.keyword_id)
  end

  test "a run stopped while the step works is not checked any further" do
    run = insert(:run, steps: build_run_steps())
    niche = insert(:niche, run: run)
    first = phrase_in_niche(run, niche, "hotel dla psów", 300)
    second = phrase_in_niche(run, niche, "hotel dla psa cena", 200)

    stub(Dirmoon.DataForSEOMock, :serp_top10, fn _request ->
      Run
      |> from(as: :run)
      |> where([run: stored_run], stored_run.id == ^run.id)
      |> Repo.update_all(set: [status: :stopped])

      serp_answer(serp_rows(["blog.example"]))
    end)

    stub(Dirmoon.LLMMock, :structured, &label_all(&1, "blog"))

    assert :ok = perform_job(CheckCompetition, %{run_id: run.id})

    assert %SerpAssessment{labels: [%{"page_type" => "blog"}], verdict: :weak} =
             Repo.get_by(SerpAssessment, run_id: run.id, keyword_id: first.keyword_id)

    refute Repo.get_by(SerpAssessment, run_id: run.id, keyword_id: second.keyword_id)
    assert %RunStep{status: :waiting, error: nil} = step(run, 5)
    assert Repo.reload!(run).status == :stopped
  end

  test "a run without phrases in niches skips the step" do
    run = insert(:run, steps: build_run_steps())

    assert :ok = perform_job(CheckCompetition, %{run_id: run.id})

    assert %RunStep{status: :skipped, result: "Brak fraz do sprawdzenia"} = step(run, 5)
  end

  test "for a new idea the current positions step is skipped and scoring is enqueued" do
    run = insert(:run, mode: :new_idea, steps: build_run_steps(%{1 => :done, 2 => :done, 3 => :done, 4 => :done}))
    phrase_in_niche(run, insert(:niche, run: run), "hotel dla psów", 100)
    expect(Dirmoon.DataForSEOMock, :serp_top10, 1, fn _request -> serp_answer([]) end)

    :ok = perform_job(CheckCompetition, %{run_id: run.id})

    assert %RunStep{status: :skipped} = step(run, 6)
    assert_enqueued(worker: Dirmoon.Workers.ScoreNiches, args: %{run_id: run.id})
  end

  test "for an existing site the current positions step is enqueued" do
    run =
      insert(:run,
        mode: :existing_site,
        domain: "psi-hotel.example",
        steps: build_run_steps(%{1 => :done, 2 => :done, 3 => :done, 4 => :done})
      )

    phrase_in_niche(run, insert(:niche, run: run), "hotel dla psów", 100)
    expect(Dirmoon.DataForSEOMock, :serp_top10, 1, fn _request -> serp_answer([]) end)

    :ok = perform_job(CheckCompetition, %{run_id: run.id})

    assert_enqueued(worker: Dirmoon.Workers.FetchCurrentPositions, args: %{run_id: run.id})
  end

  defp phrase_in_niche(run, niche, text, search_volume) do
    phrase = insert(:phrase, phrase: unique_phrase_text(text))
    insert(:volume, phrase: phrase, location_code: run.location_code, search_volume: search_volume)
    insert(:run_phrase, run: run, phrase: phrase, niche: niche)
  end

  defp phrase_in_niche_without_volume(run, niche, text) do
    insert(:run_phrase, run: run, phrase: insert(:phrase, phrase: unique_phrase_text(text)), niche: niche)
  end

  defp received_serp_requests do
    receive do
      {:serp_request, request} -> [request | received_serp_requests()]
    after
      0 -> []
    end
  end

  defp serp_rows(domains) do
    domains
    |> Enum.with_index(1)
    |> Enum.map(fn {domain, position} ->
      %{position: position, url: "https://#{domain}/", domain: domain, title: "Wynik #{position}"}
    end)
  end

  defp serp_answer(rows), do: {:ok, %{rows: rows, raw: %{"tasks" => []}, cost: Decimal.new("0.002")}}

  defp label_all(%{input: %{results: results}}, page_type) do
    results
    |> Enum.map(&%{"position" => &1.position, "page_type" => page_type})
    |> label_answer()
  end

  defp label_answer(labels), do: {:ok, %{"labels" => labels}, Decimal.new("0.001")}

  defp page_type_at(position) when position <= 4, do: "blog"
  defp page_type_at(position) when position <= 7, do: "forum"
  defp page_type_at(_position), do: "portal"

  defp age_bought_top10(run, days) do
    aged_at = DateTime.shift(DateTime.utc_now(:second), day: -days)

    ApiRequest
    |> from(as: :api_request)
    |> where([api_request: api_request], api_request.run_id == ^run.id and api_request.operation == "serp_top10")
    |> Repo.all()
    |> Enum.each(fn api_request ->
      api_request
      |> Ecto.Changeset.change(response: Map.put(api_request.response, "fetched_at", DateTime.to_iso8601(aged_at)))
      |> Repo.update!()
    end)

    SerpSnapshot
    |> from(as: :serp_snapshot)
    |> join(:inner, [serp_snapshot: serp_snapshot], run_phrase in RunPhrase,
      as: :run_phrase,
      on: run_phrase.keyword_id == serp_snapshot.keyword_id and run_phrase.run_id == ^run.id
    )
    |> Repo.update_all(set: [fetched_at: aged_at])
  end

  defp verdict(run, run_phrase) do
    Repo.get_by!(SerpAssessment, run_id: run.id, keyword_id: run_phrase.keyword_id).verdict
  end

  defp step(run, number), do: Repo.get_by!(RunStep, run_id: run.id, number: number)
end
