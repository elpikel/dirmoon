defmodule Dirmoon.Workers.FilterAndGroupTest do
  use Dirmoon.DataCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  import Mox

  alias Dirmoon.Niches.Niche
  alias Dirmoon.Phrases.RunPhrase
  alias Dirmoon.Research.ApiRequest
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.RunStep
  alias Dirmoon.Workers.CheckCompetition
  alias Dirmoon.Workers.FilterAndGroup

  test "the model's groups are stored as niches with their name, intent, reading and phrases" do
    run = insert(:run, steps: build_run_steps())
    hotel = phrase_in_run(run, "hotel dla psów", 300)
    boarding = phrase_in_run(run, "hotel dla psa cena", 200)
    grooming = phrase_in_run(run, "strzyżenie psów", 100)

    expect(Dirmoon.LLMMock, :structured, 1, fn %{task: :filter_and_group} ->
      answer(%{
        "niches" => [
          niche_answer("Hotel dla psa", [hotel.id, boarding.id]),
          niche_answer("Strzyżenie psów", [grooming.id])
        ],
        "rejected" => []
      })
    end)

    assert :ok = perform_job(FilterAndGroup, %{run_id: run.id})

    assert [first_niche, second_niche] =
             Niche
             |> from(as: :niche)
             |> where([niche: niche], niche.run_id == ^run.id)
             |> order_by([niche: niche], asc: niche.position)
             |> Repo.all()

    assert %Niche{
             name: "Hotel dla psa",
             intent: "transakcyjna",
             reading: "Ludzie szukają tej usługi. Odpowiadają im katalogi.",
             status: :proposed
           } = first_niche

    assert %Niche{name: "Strzyżenie psów"} = second_niche

    assert cluster_ids(run) == %{
             hotel.id => first_niche.id,
             boarding.id => first_niche.id,
             grooming.id => second_niche.id
           }
  end

  test "the step is done with the counts of niches and rejected phrases" do
    run = insert(:run, steps: build_run_steps())
    [first, second, third, fourth] = Enum.map(1..4, &phrase_in_run(run, "fraza #{&1}", 10 * &1))

    expect(Dirmoon.LLMMock, :structured, 1, fn _request ->
      answer(%{
        "niches" => [niche_answer("Nisza A", [first.id]), niche_answer("Nisza B", [second.id])],
        "rejected" => [%{"phrase_id" => third.id, "reason" => "inna branża"}]
      })
    end)

    :ok = perform_job(FilterAndGroup, %{run_id: run.id})

    assert %RunStep{status: :done, result: "2 nisze, 2 frazy odrzucone", output: output} = step(run, 4)
    assert output == %{"niches" => 2, "kept" => 2, "rejected" => 2}
    assert Repo.get!(RunPhrase, fourth.id).status == :rejected
  end

  test "phrases the model drops as outside the business are rejected with its reason" do
    run = insert(:run, steps: build_run_steps())
    kept = phrase_in_run(run, "hotel dla psów", 300)
    dropped = phrase_in_run(run, "hotel w zakopanem", 900)

    expect(Dirmoon.LLMMock, :structured, 1, fn _request ->
      answer(%{
        "niches" => [niche_answer("Hotel dla psa", [kept.id])],
        "rejected" => [%{"phrase_id" => dropped.id, "reason" => "  hotel dla ludzi, nie dla psów "}]
      })
    end)

    :ok = perform_job(FilterAndGroup, %{run_id: run.id})

    assert %RunPhrase{status: :rejected, rejection_reason: "hotel dla ludzi, nie dla psów", cluster_id: nil} =
             Repo.get!(RunPhrase, dropped.id)

    assert %RunPhrase{status: :kept, rejection_reason: nil} = Repo.get!(RunPhrase, kept.id)
  end

  test "a phrase id the run doesn't have is ignored" do
    run = insert(:run, steps: build_run_steps())
    kept = phrase_in_run(run, "hotel dla psów", 300)
    unknown_id = kept.id + 1_000_000

    expect(Dirmoon.LLMMock, :structured, 1, fn _request ->
      answer(%{
        "niches" => [niche_answer("Hotel dla psa", [unknown_id, kept.id]), niche_answer("Wymyślona", [unknown_id])],
        "rejected" => [%{"phrase_id" => unknown_id, "reason" => "inna branża"}]
      })
    end)

    :ok = perform_job(FilterAndGroup, %{run_id: run.id})

    assert [%Niche{id: niche_id, name: "Hotel dla psa"}] =
             Niche |> from(as: :niche) |> where([niche: niche], niche.run_id == ^run.id) |> Repo.all()

    assert cluster_ids(run) == %{kept.id => niche_id}
    assert %RunStep{output: %{"niches" => 1, "kept" => 1, "rejected" => 0}} = step(run, 4)
  end

  test "a phrase id belonging to another run is ignored and that run's phrase is left as it was" do
    run = insert(:run, steps: build_run_steps())
    kept = phrase_in_run(run, "hotel dla psów", 300)
    other_run_phrase = phrase_in_run(insert(:run), "hotel dla kota", 500)

    expect(Dirmoon.LLMMock, :structured, 1, fn _request ->
      answer(%{
        "niches" => [niche_answer("Hotel dla psa", [kept.id, other_run_phrase.id])],
        "rejected" => [%{"phrase_id" => other_run_phrase.id, "reason" => "inna branża"}]
      })
    end)

    :ok = perform_job(FilterAndGroup, %{run_id: run.id})

    assert %RunPhrase{status: :kept, rejection_reason: nil, cluster_id: nil} =
             Repo.get!(RunPhrase, other_run_phrase.id)

    assert [%Niche{id: niche_id}] =
             Niche |> from(as: :niche) |> where([niche: niche], niche.run_id == ^run.id) |> Repo.all()

    assert cluster_ids(run) == %{kept.id => niche_id}
  end

  test "phrases the model leaves out are rejected as skipped by the model" do
    run = insert(:run, steps: build_run_steps())
    kept = phrase_in_run(run, "hotel dla psów", 300)
    left_out = phrase_in_run(run, "psi hotel opinie", 40)

    expect(Dirmoon.LLMMock, :structured, 1, fn _request ->
      answer(%{"niches" => [niche_answer("Hotel dla psa", [kept.id])], "rejected" => []})
    end)

    :ok = perform_job(FilterAndGroup, %{run_id: run.id})

    assert %RunPhrase{status: :rejected, rejection_reason: "pominięta przez model", cluster_id: nil} =
             Repo.get!(RunPhrase, left_out.id)
  end

  test "a phrase named in several niches stays in the first, and a niche left empty is dropped" do
    run = insert(:run, steps: build_run_steps())
    shared = phrase_in_run(run, "hotel dla psów", 300)
    other = phrase_in_run(run, "strzyżenie psów", 100)

    expect(Dirmoon.LLMMock, :structured, 1, fn _request ->
      answer(%{
        "niches" => [
          niche_answer("Hotel dla psa", [shared.id, shared.id]),
          niche_answer("Duplikat", [shared.id]),
          niche_answer("Strzyżenie", [other.id])
        ],
        "rejected" => [%{"phrase_id" => shared.id, "reason" => "inna branża"}]
      })
    end)

    :ok = perform_job(FilterAndGroup, %{run_id: run.id})

    assert [
             %Niche{id: first_id, name: "Hotel dla psa", position: 1},
             %Niche{id: second_id, name: "Strzyżenie", position: 2}
           ] =
             Niche
             |> from(as: :niche)
             |> where([niche: niche], niche.run_id == ^run.id)
             |> order_by([niche: niche], asc: niche.position)
             |> Repo.all()

    assert cluster_ids(run) == %{shared.id => first_id, other.id => second_id}
    assert Repo.get!(RunPhrase, shared.id).status == :kept
  end

  test "niche names and readings are trimmed and a niche without a name is dropped" do
    run = insert(:run, steps: build_run_steps())
    named = phrase_in_run(run, "hotel dla psów", 300)
    nameless = phrase_in_run(run, "strzyżenie psów", 100)

    expect(Dirmoon.LLMMock, :structured, 1, fn _request ->
      answer(%{
        "niches" => [
          %{
            "name" => "  Hotel dla psa ",
            "intent" => " lokalna ",
            "reading" => " Zdanie pierwsze. Zdanie drugie. ",
            "phrase_ids" => [named.id]
          },
          %{"name" => "   ", "intent" => "lokalna", "reading" => "Bez nazwy.", "phrase_ids" => [nameless.id]}
        ],
        "rejected" => []
      })
    end)

    :ok = perform_job(FilterAndGroup, %{run_id: run.id})

    assert [%Niche{name: "Hotel dla psa", intent: "lokalna", reading: "Zdanie pierwsze. Zdanie drugie."}] =
             Niche |> from(as: :niche) |> where([niche: niche], niche.run_id == ^run.id) |> Repo.all()

    assert %RunPhrase{status: :rejected, rejection_reason: "pominięta przez model"} = Repo.get!(RunPhrase, nameless.id)
  end

  test "a niche name longer than the column allows is cut to the maximum length and stored" do
    run = insert(:run, steps: build_run_steps())
    kept = phrase_in_run(run, "hotel dla psów", 300)
    long_name = String.duplicate("ż", Niche.max_name_length() + 40)

    expect(Dirmoon.LLMMock, :structured, 1, fn _request ->
      answer(%{"niches" => [niche_answer(long_name, [kept.id])], "rejected" => []})
    end)

    assert :ok = perform_job(FilterAndGroup, %{run_id: run.id})

    assert [%Niche{name: name}] =
             Niche |> from(as: :niche) |> where([niche: niche], niche.run_id == ^run.id) |> Repo.all()

    assert name == String.duplicate("ż", Niche.max_name_length())
    assert %RunStep{status: :done} = step(run, 4)
  end

  test "the request lists the run's phrases by id with their country volumes and nothing from other runs" do
    run = insert(:run, steps: build_run_steps())
    with_volume = phrase_in_run(run, "hotel dla psów", 300)
    without_volume = run_phrase_without_volume(run, "psi hotel nocleg")
    other_run_phrase = phrase_in_run(insert(:run), "hotel dla kota", 500)
    test_process = self()

    expect(Dirmoon.LLMMock, :structured, 1, fn request ->
      send(test_process, {:llm_request, request})
      answer(%{"niches" => [niche_answer("Hotel dla psa", [with_volume.id])], "rejected" => []})
    end)

    :ok = perform_job(FilterAndGroup, %{run_id: run.id})

    assert_received {:llm_request, %{task: :filter_and_group, prompt: prompt, input: %{phrases: phrases}}}

    assert phrases == [
             %{id: with_volume.id, phrase: with_volume.phrase.phrase, volume: 300},
             %{id: without_volume.id, phrase: without_volume.phrase.phrase, volume: nil}
           ]

    assert prompt =~ "#{with_volume.id}: #{with_volume.phrase.phrase} (300)"
    assert prompt =~ "#{without_volume.id}: #{without_volume.phrase.phrase} (brak danych)"
    refute prompt =~ other_run_phrase.phrase.phrase
    refute Enum.any?(phrases, &(&1.id == other_run_phrase.id))
  end

  test "the prompt describes the business so the model can drop phrases outside it" do
    run =
      insert(:run,
        description: "Hotel dla psów pod miastem",
        priority_services: ["hotel dla psów", "spacery z psem"],
        city: "Gdańsk",
        steps: build_run_steps()
      )

    kept = phrase_in_run(run, "hotel dla psów", 300)
    test_process = self()

    expect(Dirmoon.LLMMock, :structured, 1, fn request ->
      send(test_process, {:llm_request, request})
      answer(%{"niches" => [niche_answer("Hotel dla psa", [kept.id])], "rejected" => []})
    end)

    :ok = perform_job(FilterAndGroup, %{run_id: run.id})

    assert_received {:llm_request, %{prompt: prompt, system: system}}
    assert prompt =~ "Hotel dla psów pod miastem"
    assert prompt =~ "hotel dla psów, spacery z psem"
    assert prompt =~ "Gdańsk"
    assert prompt =~ "nowy pomysł"
    assert system =~ "identyfikator"
  end

  test "the prompt of an existing site names its domain" do
    run = insert(:run, mode: :existing_site, domain: "hotel-testowy.example", steps: build_run_steps())
    kept = phrase_in_run(run, "hotel dla psów", 300)
    test_process = self()

    expect(Dirmoon.LLMMock, :structured, 1, fn request ->
      send(test_process, {:llm_request, request})
      answer(%{"niches" => [niche_answer("Hotel dla psa", [kept.id])], "rejected" => []})
    end)

    :ok = perform_job(FilterAndGroup, %{run_id: run.id})

    assert_received {:llm_request, %{prompt: prompt}}
    assert prompt =~ "Tryb: istniejąca strona, domena: hotel-testowy.example."
  end

  test "a niche name or rejection reason that is not text counts as missing" do
    run = insert(:run, steps: build_run_steps())
    kept = phrase_in_run(run, "hotel dla psów", 300)
    numbered = phrase_in_run(run, "hotel dla kotów", 200)
    dropped = phrase_in_run(run, "hotel w górach", 100)

    expect(Dirmoon.LLMMock, :structured, 1, fn _request ->
      answer(%{
        "niches" => [
          niche_answer("Hotel dla psa", [kept.id]),
          %{"name" => 42, "intent" => 7, "reading" => nil, "phrase_ids" => [numbered.id]}
        ],
        "rejected" => [%{"phrase_id" => dropped.id, "reason" => ["poza ofertą"]}]
      })
    end)

    :ok = perform_job(FilterAndGroup, %{run_id: run.id})

    assert [%Niche{name: "Hotel dla psa"}] =
             Niche |> from(as: :niche) |> where([niche: niche], niche.run_id == ^run.id) |> Repo.all()

    assert %RunPhrase{status: :rejected, rejection_reason: "pominięta przez model"} = Repo.get!(RunPhrase, numbered.id)
    assert %RunPhrase{status: :rejected, rejection_reason: "odrzucona przez model"} = Repo.get!(RunPhrase, dropped.id)
  end

  test "the competition step is enqueued after the phrases are grouped" do
    run = insert(:run, steps: build_run_steps(%{1 => :done, 2 => :done, 3 => :done}))
    kept = phrase_in_run(run, "hotel dla psów", 300)

    expect(Dirmoon.LLMMock, :structured, 1, fn _request ->
      answer(%{"niches" => [niche_answer("Hotel dla psa", [kept.id])], "rejected" => []})
    end)

    :ok = perform_job(FilterAndGroup, %{run_id: run.id})

    assert_enqueued(worker: CheckCompetition, args: %{run_id: run.id})
  end

  test "re-running the step after a reset reuses the stored answer and doesn't duplicate niches" do
    run = insert(:run, steps: build_run_steps())
    kept = phrase_in_run(run, "hotel dla psów", 300)
    dropped = phrase_in_run(run, "hotel w zakopanem", 900)

    expect(Dirmoon.LLMMock, :structured, 1, fn _request ->
      answer(%{
        "niches" => [niche_answer("Hotel dla psa", [kept.id])],
        "rejected" => [%{"phrase_id" => dropped.id, "reason" => "inna branża"}]
      })
    end)

    :ok = perform_job(FilterAndGroup, %{run_id: run.id})
    run |> step(4) |> RunStep.reset_changeset() |> Repo.update!()

    assert :ok = perform_job(FilterAndGroup, %{run_id: run.id})

    assert [%Niche{id: niche_id}] =
             Niche |> from(as: :niche) |> where([niche: niche], niche.run_id == ^run.id) |> Repo.all()

    assert cluster_ids(run) == %{kept.id => niche_id}
    assert %RunPhrase{status: :rejected, rejection_reason: "inna branża"} = Repo.get!(RunPhrase, dropped.id)
    assert %RunStep{status: :done, result: "1 nisza, 1 fraza odrzucona"} = step(run, 4)
    assert [%ApiRequest{service: "llm", operation: "filter_and_group"}] = Repo.all(ApiRequest)
  end

  test "an answer with no valid niche is not recorded and the retry asks the model again" do
    run = insert(:run, steps: build_run_steps())
    kept = phrase_in_run(run, "hotel dla psów", 300)

    Dirmoon.LLMMock
    |> expect(:structured, 1, fn _request ->
      answer(%{"niches" => [niche_answer("Pusta", [kept.id + 1_000_000])], "rejected" => []})
    end)
    |> expect(:structured, 1, fn _request ->
      answer(%{"niches" => [niche_answer("Hotel dla psa", [kept.id])], "rejected" => []})
    end)

    assert {:error, "Model nie zwrócił żadnej niszy"} = perform_job(FilterAndGroup, %{run_id: run.id}, attempt: 1)
    assert Repo.all(ApiRequest) == []
    assert Niche |> from(as: :niche) |> where([niche: niche], niche.run_id == ^run.id) |> Repo.all() == []

    assert :ok = perform_job(FilterAndGroup, %{run_id: run.id}, attempt: 2)

    assert [%Niche{name: "Hotel dla psa"}] =
             Niche |> from(as: :niche) |> where([niche: niche], niche.run_id == ^run.id) |> Repo.all()

    assert [%ApiRequest{operation: "filter_and_group"}] = Repo.all(ApiRequest)
  end

  test "a run without phrases fails the step on the last attempt without asking the model" do
    run = insert(:run, steps: build_run_steps())
    expect(Dirmoon.LLMMock, :structured, 0, fn _request -> answer(%{}) end)

    assert {:cancel, "Brak fraz do pogrupowania"} = perform_job(FilterAndGroup, %{run_id: run.id}, attempt: 3)

    assert %RunStep{status: :failed, error: "Brak fraz do pogrupowania"} = step(run, 4)
    assert %Run{status: :failed} = Repo.get!(Run, run.id)
  end

  test "without an LLM provider the step and the run fail with a readable reason" do
    run = insert(:run, steps: build_run_steps())
    phrase_in_run(run, "hotel dla psów", 300)
    expect(Dirmoon.LLMMock, :structured, 1, fn _request -> {:error, :llm_not_configured} end)

    assert {:cancel, :llm_not_configured} = perform_job(FilterAndGroup, %{run_id: run.id})

    assert %RunStep{status: :failed, error: "Brak klucza API OpenAI"} = step(run, 4)
    assert %Run{status: :failed} = Repo.get!(Run, run.id)
    assert Niche |> from(as: :niche) |> where([niche: niche], niche.run_id == ^run.id) |> Repo.all() == []
    assert all_enqueued() == []
  end

  defp phrase_in_run(run, text, search_volume) do
    phrase = insert(:phrase, phrase: unique_phrase_text(text))
    insert(:metrics, phrase: phrase, location_code: run.location_code, search_volume: search_volume)
    insert(:run_phrase, run: run, phrase: phrase)
  end

  defp run_phrase_without_volume(run, text) do
    insert(:run_phrase, run: run, phrase: build(:phrase, phrase: unique_phrase_text(text)))
  end

  defp niche_answer(name, phrase_ids) do
    %{
      "name" => name,
      "intent" => "transakcyjna",
      "reading" => "Ludzie szukają tej usługi. Odpowiadają im katalogi.",
      "phrase_ids" => phrase_ids
    }
  end

  defp answer(body), do: {:ok, body, Decimal.new("0.004")}

  defp cluster_ids(run) do
    RunPhrase
    |> from(as: :run_phrase)
    |> where([run_phrase: run_phrase], run_phrase.run_id == ^run.id and not is_nil(run_phrase.cluster_id))
    |> select([run_phrase: run_phrase], {run_phrase.id, run_phrase.cluster_id})
    |> Repo.all()
    |> Map.new()
  end

  defp step(run, number), do: Repo.get_by!(RunStep, run_id: run.id, number: number)
end
