defmodule Dirmoon.Workers.GenerateSeedsTest do
  use Dirmoon.DataCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  import Mox

  alias Dirmoon.Research.ApiRequest
  alias Dirmoon.Research.Pipeline
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.RunStep
  alias Dirmoon.Workers.ExpandPhrases
  alias Dirmoon.Workers.GenerateSeeds

  test "step 1 is done with the counts of seeds and questions and stores them as its output" do
    run = insert(:run, steps: build_run_steps())
    seeds = seed_list(18)
    questions = Enum.map(1..12, &"Pytanie klienta #{&1}?")

    expect(Dirmoon.LLMMock, :structured, 1, fn %{task: :seeds} ->
      {:ok, %{"seeds" => seeds, "questions" => questions}, Decimal.new("0.003")}
    end)

    assert :ok = perform_job(GenerateSeeds, %{run_id: run.id})

    assert %RunStep{status: :done, result: "18 fraz startowych, 12 pytań", output: output} = step(run, 1)
    assert output == %{"seeds" => seeds, "questions" => questions}
  end

  test "seeds are trimmed, lowercased and deduplicated, and blanks are dropped" do
    run = insert(:run, steps: build_run_steps())
    messy_seeds = ["  Hotel Dla Psów ", "hotel dla psów", "", "   " | seed_list(10)]

    expect(Dirmoon.LLMMock, :structured, 1, fn _request ->
      {:ok, %{"seeds" => messy_seeds, "questions" => [" Ile to kosztuje? ", "Ile to kosztuje?", ""]},
       Decimal.new("0.003")}
    end)

    :ok = perform_job(GenerateSeeds, %{run_id: run.id})

    assert %RunStep{result: "11 fraz startowych, 1 pytanie", output: output} = step(run, 1)
    assert output == %{"seeds" => ["hotel dla psów" | seed_list(10)], "questions" => ["Ile to kosztuje?"]}
  end

  test "more than twenty seeds keep the first twenty" do
    run = insert(:run, steps: build_run_steps())

    expect(Dirmoon.LLMMock, :structured, 1, fn _request ->
      {:ok, %{"seeds" => seed_list(24), "questions" => ["Gdzie?", "Kiedy?", "Ile?"]}, Decimal.new("0.003")}
    end)

    :ok = perform_job(GenerateSeeds, %{run_id: run.id})

    assert %RunStep{result: "20 fraz startowych, 3 pytania", output: %{"seeds" => seeds}} = step(run, 1)
    assert seeds == seed_list(20)
  end

  test "the prompt asks for seeds about the Priority Services first" do
    run = insert(:run, priority_services: ["strzyżenie psów", "kąpiel psów"], steps: build_run_steps())
    test_process = self()

    expect(Dirmoon.LLMMock, :structured, 1, fn request ->
      send(test_process, {:llm_request, request})
      valid_answer()
    end)

    :ok = perform_job(GenerateSeeds, %{run_id: run.id})

    assert_received {:llm_request, %{prompt: prompt, input: %{priority_services: ["strzyżenie psów", "kąpiel psów"]}}}
    assert prompt =~ "Najpierw podaj frazy startowe dotyczące tych usług: strzyżenie psów, kąpiel psów"
  end

  test "the prompt asks for city variants when the run has a city" do
    run = insert(:run, city: "Gdańsk", steps: build_run_steps())
    test_process = self()

    expect(Dirmoon.LLMMock, :structured, 1, fn request ->
      send(test_process, {:llm_request, request})
      valid_answer()
    end)

    :ok = perform_job(GenerateSeeds, %{run_id: run.id})

    assert_received {:llm_request, %{prompt: prompt, input: %{city: "Gdańsk"}}}
    assert prompt =~ "Dodaj warianty z nazwą miasta (np. „… gdańsk”)"
  end

  test "the prompt asks for no city variants when the run has no city" do
    run = insert(:run, city: nil, steps: build_run_steps())
    test_process = self()

    expect(Dirmoon.LLMMock, :structured, 1, fn request ->
      send(test_process, {:llm_request, request})
      valid_answer()
    end)

    :ok = perform_job(GenerateSeeds, %{run_id: run.id})

    assert_received {:llm_request, %{prompt: prompt, input: %{city: nil}}}
    refute prompt =~ "nazwą miasta"
  end

  test "the prompt states the mode and the domain of an existing site" do
    run = insert(:run, mode: :existing_site, domain: "psiehotele.example", steps: build_run_steps())
    test_process = self()

    expect(Dirmoon.LLMMock, :structured, 1, fn request ->
      send(test_process, {:llm_request, request})
      valid_answer()
    end)

    :ok = perform_job(GenerateSeeds, %{run_id: run.id})

    assert_received {:llm_request, %{task: :seeds, prompt: prompt}}
    assert prompt =~ "istniejąca strona"
    assert prompt =~ "psiehotele.example"
  end

  test "the expansion step is enqueued after the seeds are generated" do
    run = insert(:run, steps: build_run_steps())
    expect(Dirmoon.LLMMock, :structured, 1, fn _request -> valid_answer() end)

    :ok = perform_job(GenerateSeeds, %{run_id: run.id})

    assert_enqueued(worker: ExpandPhrases, args: %{run_id: run.id})
  end

  test "the LLM call is recorded with its cost and is not repeated for the same run" do
    run = insert(:run, steps: build_run_steps())
    expect(Dirmoon.LLMMock, :structured, 1, fn _request -> valid_answer() end)

    :ok = perform_job(GenerateSeeds, %{run_id: run.id})
    run |> step(1) |> RunStep.reset_changeset() |> Repo.update!()

    assert :ok = perform_job(GenerateSeeds, %{run_id: run.id})

    assert %RunStep{status: :done, output: %{"seeds" => seeds}} = step(run, 1)
    assert seeds == seed_list(10)
    assert [%ApiRequest{service: "llm", operation: "seeds", cost: cost}] = Repo.all(ApiRequest)
    assert Decimal.equal?(cost, Decimal.new("0.003"))
  end

  test "step 1 writes only its own output and the LLM request record" do
    run = insert(:run, steps: build_run_steps())
    expect(Dirmoon.LLMMock, :structured, 1, fn _request -> valid_answer() end)

    :ok = perform_job(GenerateSeeds, %{run_id: run.id})

    assert Enum.map(2..8, &step(run, &1).output) == List.duplicate(nil, 7)
    assert Repo.aggregate(ApiRequest, :count) == 1
  end

  test "without an LLM provider the step and the run fail with a readable reason and nothing is enqueued" do
    run = insert(:run, steps: build_run_steps())
    expect(Dirmoon.LLMMock, :structured, 1, fn _request -> {:error, :llm_not_configured} end)

    assert {:cancel, :llm_not_configured} = perform_job(GenerateSeeds, %{run_id: run.id})

    assert %RunStep{status: :failed, error: "Brak klucza API OpenAI"} = step(run, 1)
    assert %Run{status: :failed} = Repo.get!(Run, run.id)
    assert Enum.map(2..8, &step(run, &1).status) == List.duplicate(:waiting, 7)
    assert all_enqueued() == []
  end

  test "too few seeds before the last attempt return an error and record no LLM request" do
    run = insert(:run, steps: build_run_steps())
    expect(Dirmoon.LLMMock, :structured, 1, fn _request -> too_few_seeds_answer() end)

    assert {:error, "Model zwrócił za mało fraz startowych"} =
             perform_job(GenerateSeeds, %{run_id: run.id}, attempt: 1)

    assert %Run{status: :running} = Repo.get!(Run, run.id)
    assert Repo.all(ApiRequest) == []
  end

  test "a retry after too few seeds asks the LLM again and records only the valid answer" do
    run = insert(:run, steps: build_run_steps())

    Dirmoon.LLMMock
    |> expect(:structured, 1, fn _request -> too_few_seeds_answer() end)
    |> expect(:structured, 1, fn _request -> valid_answer() end)

    {:error, _reason} = perform_job(GenerateSeeds, %{run_id: run.id}, attempt: 1)

    assert :ok = perform_job(GenerateSeeds, %{run_id: run.id}, attempt: 2)

    assert %RunStep{status: :done, output: %{"seeds" => seeds}} = step(run, 1)
    assert seeds == seed_list(10)
    assert [%ApiRequest{operation: "seeds"}] = Repo.all(ApiRequest)
  end

  test "resuming a run whose seeds failed on the last attempt asks the LLM again" do
    run = insert(:run, steps: build_run_steps())

    Dirmoon.LLMMock
    |> expect(:structured, 1, fn _request -> too_few_seeds_answer() end)
    |> expect(:structured, 1, fn _request -> valid_answer() end)

    {:cancel, _reason} = perform_job(GenerateSeeds, %{run_id: run.id}, attempt: 3)
    :ok = Pipeline.resume(Repo.get!(Run, run.id))

    assert_enqueued(worker: GenerateSeeds, args: %{run_id: run.id})
    assert :ok = perform_job(GenerateSeeds, %{run_id: run.id})

    assert %RunStep{status: :done, output: %{"seeds" => seeds}} = step(run, 1)
    assert seeds == seed_list(10)
  end

  test "too few seeds on the last attempt fail the step and the run" do
    run = insert(:run, steps: build_run_steps())
    expect(Dirmoon.LLMMock, :structured, 1, fn _request -> too_few_seeds_answer() end)

    assert {:cancel, "Model zwrócił za mało fraz startowych"} =
             perform_job(GenerateSeeds, %{run_id: run.id}, attempt: 3)

    assert %RunStep{status: :failed, error: "Model zwrócił za mało fraz startowych"} = step(run, 1)
    assert %Run{status: :failed} = Repo.get!(Run, run.id)
    assert all_enqueued() == []
  end

  defp seed_list(count), do: Enum.map(1..count, &"fraza startowa #{&1}")

  defp valid_answer do
    {:ok, %{"seeds" => seed_list(10), "questions" => ["Ile kosztuje hotel dla psa?"]}, Decimal.new("0.003")}
  end

  defp too_few_seeds_answer do
    {:ok, %{"seeds" => [" Hotel dla psów", "hotel dla psów", "hotel dla kota"], "questions" => []}, Decimal.new("0.003")}
  end

  defp step(run, number), do: Repo.get_by!(RunStep, run_id: run.id, number: number)
end
