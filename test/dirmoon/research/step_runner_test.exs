defmodule Dirmoon.Research.StepRunnerTest do
  use Dirmoon.DataCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  alias Dirmoon.Accounts.Scope
  alias Dirmoon.Research
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.RunStep
  alias Dirmoon.Research.StepRunner
  alias Dirmoon.Workers.CheckCompetition
  alias Dirmoon.Workers.ExpandPhrases

  test "a finished Step is stored as done with its result and output" do
    run = insert(:run, steps: build_run_steps())

    assert :ok =
             StepRunner.run(job_for(run), 1, fn _run -> {:ok, %{result: "14 załążków", output: %{"seeds" => ["a"]}}} end)

    assert %RunStep{status: :done, result: "14 załążków", output: %{"seeds" => ["a"]}} = step(run, 1)
    assert step(run, 1).finished_at
  end

  test "decimals, dates and atoms in a Step's output are stored as JSON strings" do
    run = insert(:run, steps: build_run_steps())
    output = %{"cost" => Decimal.new("0.66"), "day" => ~D[2026-11-24], "verdict" => :weak, "skipped" => nil}

    :ok = StepRunner.run(job_for(run), 1, fn _run -> {:ok, %{result: "gotowe", output: output}} end)

    assert [%{"cost" => "0.66", "day" => "2026-11-24", "verdict" => "weak", "skipped" => nil}] =
             stored_json(%{table: "run_steps", column: "output", where: "run_id = $1 AND number = 1", value: run.id})
  end

  test "a skipped Step stores no output" do
    run = insert(:run, steps: build_run_steps())

    :ok = StepRunner.run(job_for(run), 1, fn _run -> {:skip, "pominięty"} end)

    assert %RunStep{status: :skipped, output: nil} = step(run, 1)
  end

  test "a finished Step enqueues the next Step" do
    run = insert(:run, steps: build_run_steps())

    :ok = StepRunner.run(job_for(run), 1, fn _run -> {:ok, %{result: "gotowe", output: %{}}} end)

    assert_enqueued(worker: ExpandPhrases, args: %{run_id: run.id})
  end

  test "subscribers to the run are notified when a Step finishes" do
    run = insert(:run, steps: build_run_steps())
    :ok = Research.subscribe(run)

    :ok = StepRunner.run(job_for(run), 1, fn _run -> {:ok, %{result: "gotowe", output: %{}}} end)

    run_id = run.id
    assert_receive {:run_updated, ^run_id}
  end

  test "the step function receives the run" do
    run = insert(:run, steps: build_run_steps())
    test_process = self()

    :ok =
      StepRunner.run(job_for(run), 1, fn received_run ->
        send(test_process, {:received, received_run})
        {:ok, %{result: "gotowe", output: %{}}}
      end)

    assert_received {:received, %Run{id: run_id}}
    assert run_id == run.id
  end

  test "a skipped Step is stored as skipped with its reason and the next Step is enqueued" do
    run = insert(:run, steps: build_run_steps(%{1 => :done, 2 => :done, 3 => :done}))

    :ok = StepRunner.run(job_for(run), 4, fn _run -> {:skip, "Brak fraz do oceny"} end)

    assert %RunStep{status: :skipped, result: "Brak fraz do oceny"} = step(run, 4)
    assert_enqueued(worker: CheckCompetition, args: %{run_id: run.id})
  end

  test "a Step already done is not run again and the pipeline moves on" do
    run = insert(:run, steps: build_run_steps(%{1 => :done}))

    assert :ok = StepRunner.run(job_for(run), 1, fn _run -> flunk("the step ran again") end)

    assert_enqueued(worker: ExpandPhrases, args: %{run_id: run.id})
  end

  test "a Step of a stopped run does nothing" do
    run = insert(:run, status: :stopped, steps: build_run_steps())

    assert :ok = StepRunner.run(job_for(run), 1, fn _run -> flunk("the step ran") end)

    assert step(run, 1).status == :waiting
    assert all_enqueued() == []
  end

  test "an error before the last attempt is returned so the job is retried" do
    run = insert(:run, steps: build_run_steps())

    assert {:error, :timeout} = StepRunner.run(job_for(run, attempt: 1), 1, fn _run -> {:error, :timeout} end)

    assert Repo.reload!(run).status == :running
  end

  test "an error on the last attempt fails the Step with a readable reason" do
    run = insert(:run, steps: build_run_steps())

    assert {:cancel, _reason} =
             StepRunner.run(job_for(run, attempt: 3), 1, fn _run -> {:error, "DataForSEO odpowiedział 500"} end)

    assert %RunStep{status: :failed, error: "DataForSEO odpowiedział 500"} = step(run, 1)
  end

  test "an error on the last attempt fails the run and leaves later Steps waiting" do
    run = insert(:run, steps: build_run_steps())

    StepRunner.run(job_for(run, attempt: 3), 1, fn _run -> {:error, :timeout} end)

    assert Repo.reload!(run).status == :failed
    assert run |> later_steps(1) |> Enum.map(& &1.status) |> Enum.uniq() == [:waiting]
    assert all_enqueued() == []
  end

  test "an unexpected error reason is shown as an unexpected error" do
    run = insert(:run, steps: build_run_steps())

    StepRunner.run(job_for(run, attempt: 3), 1, fn _run -> {:error, :timeout} end)

    assert step(run, 1).error == "Nieoczekiwany błąd: :timeout"
  end

  test "a client that is not configured reads as a message naming the missing setting" do
    assert StepRunner.readable_reason(:llm_not_configured) == "Brak klucza API OpenAI"
    assert StepRunner.readable_reason(:data_for_seo_not_configured) == "Brak danych logowania DataForSEO"
    assert StepRunner.readable_reason(:hosting_not_configured) == "Brak tokenu Netlify"
  end

  test "a text reason reads as itself" do
    assert StepRunner.readable_reason("Model zwrócił niepoprawny brief") == "Model zwrócił niepoprawny brief"
  end

  test "an exception reads as an unexpected error with its message" do
    assert StepRunner.readable_reason(RuntimeError.exception("boom")) == "Nieoczekiwany błąd: boom"
  end

  test "any other reason reads as an unexpected error" do
    assert StepRunner.readable_reason({:http, 500}) == "Nieoczekiwany błąd: {:http, 500}"
  end

  test "a client that is not configured fails the Step on the first attempt" do
    run = insert(:run, steps: build_run_steps())

    assert {:cancel, :llm_not_configured} =
             StepRunner.run(job_for(run, attempt: 1), 1, fn _run -> {:error, :llm_not_configured} end)

    assert %RunStep{status: :failed, error: "Brak klucza API OpenAI"} = step(run, 1)
    assert Repo.reload!(run).status == :failed
  end

  test "subscribers to the run are notified when a Step fails" do
    run = insert(:run, steps: build_run_steps())
    :ok = Research.subscribe(run)

    StepRunner.run(job_for(run, attempt: 1), 1, fn _run -> {:error, :data_for_seo_not_configured} end)

    run_id = run.id
    assert_receive {:run_updated, ^run_id}
    assert step(run, 1).error == "Brak danych logowania DataForSEO"
  end

  test "an error on the last attempt leaves a run stopped meanwhile as stopped" do
    account = insert(:account)
    run = insert(:run, account: account, steps: build_run_steps())
    scope = Scope.for_user(build(:user), account)

    StepRunner.run(job_for(run, attempt: 3), 1, fn _run ->
      {:ok, _stopped_run} = Research.stop_run(scope, run.id)
      {:error, :timeout}
    end)

    assert Repo.reload!(run).status == :stopped
  end

  test "a Step that finds its run stopped waits again without an error, even on the last attempt" do
    run = insert(:run, steps: build_run_steps(%{1 => :done, 2 => :done, 3 => :done, 4 => :done}))

    assert :ok =
             StepRunner.run(job_for(run, attempt: 3), 5, fn _run ->
               mark_stopped(run)
               :stopped
             end)

    assert %RunStep{status: :waiting, error: nil, started_at: nil, finished_at: nil} = step(run, 5)
    assert Repo.reload!(run).status == :stopped
    assert all_enqueued() == []
  end

  test "a queued Step 8 runs and the run awaits a choice again" do
    run = insert(:run, steps: build_run_steps(Map.put(done_through(7), 8, :queued)))

    assert :ok = StepRunner.run(job_for(run), 8, fn _run -> {:ok, %{result: "Brief gotowy", output: %{}}} end)

    assert %RunStep{status: :done, result: "Brief gotowy"} = step(run, 8)
    assert Repo.reload!(run).status == :awaiting_choice
  end

  test "a Step 8 that finds its run stopped is queued again so a resume runs it" do
    run = insert(:run, steps: build_run_steps(Map.put(done_through(7), 8, :queued)))

    assert :ok =
             StepRunner.run(job_for(run), 8, fn _run ->
               mark_stopped(run)
               :stopped
             end)

    assert %RunStep{status: :queued, error: nil, started_at: nil} = step(run, 8)
    assert Repo.reload!(run).status == :stopped
  end

  test "a Step that finds its run resumed meanwhile snoozes so the same job runs the Step again" do
    run = insert(:run, steps: build_run_steps(%{1 => :done, 2 => :done, 3 => :done, 4 => :done}))

    assert {:snooze, _seconds} = StepRunner.run(job_for(run, attempt: 3), 5, fn _run -> :stopped end)

    assert Repo.reload!(run).status == :running
    assert step(run, 5).status == :waiting
  end

  test "subscribers to the run are notified when a Step finds its run stopped" do
    run = insert(:run, steps: build_run_steps())
    :ok = Research.subscribe(run)

    :ok =
      StepRunner.run(job_for(run), 1, fn _run ->
        mark_stopped(run)
        :stopped
      end)

    run_id = run.id
    assert_receive {:run_updated, ^run_id}
    assert_receive {:run_updated, ^run_id}
  end

  test "a step function that raises on the last attempt fails the Step" do
    run = insert(:run, steps: build_run_steps())

    StepRunner.run(job_for(run, attempt: 3), 1, fn _run -> raise ArgumentError, "zła odpowiedź" end)

    assert %RunStep{status: :failed, error: "Nieoczekiwany błąd: zła odpowiedź"} = step(run, 1)
  end

  test "a step function that raises before the last attempt returns the exception so the job is retried" do
    run = insert(:run, steps: build_run_steps())

    assert {:error, %ArgumentError{message: "zła odpowiedź"}} =
             StepRunner.run(job_for(run, attempt: 1), 1, fn _run -> raise ArgumentError, "zła odpowiedź" end)

    assert %RunStep{status: :running} = step(run, 1)
    assert Repo.reload!(run).status == :running
  end

  test "a step function that raises on the last attempt fails the run" do
    run = insert(:run, steps: build_run_steps())

    assert {:cancel, %ArgumentError{}} =
             StepRunner.run(job_for(run, attempt: 3), 1, fn _run -> raise ArgumentError, "zła odpowiedź" end)

    assert Repo.reload!(run).status == :failed
  end

  test "a step function returning an unexpected value before the last attempt is retried" do
    run = insert(:run, steps: build_run_steps())

    assert {:error, _reason} = StepRunner.run(job_for(run, attempt: 1), 1, fn _run -> :unexpected end)

    assert %RunStep{status: :running} = step(run, 1)
    assert Repo.reload!(run).status == :running
  end

  test "a step function returning an unexpected value on the last attempt fails the Step and the run" do
    run = insert(:run, steps: build_run_steps())

    assert {:cancel, _reason} = StepRunner.run(job_for(run, attempt: 3), 1, fn _run -> :unexpected end)

    assert %RunStep{status: :failed, error: "Nieoczekiwany błąd: {:unexpected_step_outcome, :unexpected}"} =
             step(run, 1)

    assert Repo.reload!(run).status == :failed
  end

  defp done_through(last_number), do: Map.new(1..last_number, &{&1, :done})

  defp job_for(run, opts \\ []) do
    %Oban.Job{args: %{"run_id" => run.id}, attempt: Keyword.get(opts, :attempt, 1), max_attempts: 3}
  end

  defp mark_stopped(run) do
    Run
    |> from(as: :run)
    |> where([run: stored_run], stored_run.id == ^run.id)
    |> Repo.update_all(set: [status: :stopped])
  end

  defp step(run, number) do
    Repo.get_by!(RunStep, run_id: run.id, number: number)
  end

  defp later_steps(run, number) do
    RunStep
    |> from(as: :run_step)
    |> where([run_step: run_step], run_step.run_id == ^run.id and run_step.number > ^number)
    |> Repo.all()
  end
end
