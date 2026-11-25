defmodule Dirmoon.Research.Pipeline do
  @moduledoc """
  Moves a Research Run along its Steps. Steps 1–7 follow each other on their
  own; Step 6 is skipped when it doesn't apply to the run's Mode. After Step 7
  the run awaits a Niche choice; Step 8 starts only through
  `enqueue_step/2` or `start_step/2`, which mark it `:queued` until its
  job starts; a run with a queued or running Step never settles. Each Step
  runs as an Oban job on the `pipeline` queue, one Step at a time per run:
  a queued Step 8 left behind another Step gets its job when that one
  finishes.
  """

  import Ecto.Query

  alias Dirmoon.Repo
  alias Dirmoon.Research
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.RunStep
  alias Dirmoon.Research.Steps

  @max_attempts 3
  @user_triggered_numbers Steps.all() |> Enum.reject(& &1.auto_chained?) |> Enum.map(& &1.number)

  @doc """
  Enqueues the next waiting Step of a running run, skipping Steps that don't
  apply to its Mode. When Steps 1–7 are all finished and no Step is running,
  a queued Step 8 is enqueued (its job is unique, so one already enqueued
  isn't doubled); with none queued, the run awaits a choice. Does nothing
  for a run that isn't running.
  """
  def advance(%Run{id: run_id}) do
    run_id
    |> load_run_with_steps()
    |> advance_loaded_run()
  end

  @doc """
  Starts a user-triggered Step (8) and tells the run's subscribers:
  `start_step/2` in its own transaction, then a run broadcast. Same
  precondition as `start_step/2`.
  """
  def enqueue_step(%Run{} = run, number) when number in @user_triggered_numbers do
    with {:ok, updated_run} <- Repo.transact(fn -> start_step(run, number) end) do
      Research.broadcast_run_updated(updated_run)
      {:ok, updated_run}
    end
  end

  @doc """
  Starts a user-triggered Step (8) without telling subscribers: clears
  its earlier result, marks it `:queued`, sets the run running and enqueues
  the Step's worker. For a caller that runs it inside its own transaction and
  broadcasts after the commit. Returns `{:ok, run}`.

  Precondition, checked by the caller with the run locked: the run is idle
  (`Dirmoon.Research.idle?/1`), so no other Step is queued or running.
  """
  def start_step(%Run{} = run, number) when number in @user_triggered_numbers do
    queue_step(run, number)
    updated_run = run |> Ecto.Changeset.change(status: :running) |> Repo.update!()
    insert_step_job(updated_run, Steps.get!(number))
    {:ok, updated_run}
  end

  @doc """
  Resumes a stopped or failed run, which then is running. Failed and
  interrupted Steps 1–7 wait again and the first one that isn't done or
  skipped is enqueued. A Step 8 that was queued or interrupted is queued and
  enqueued again. A Step 8 that failed is not retried: its page was already
  marked failed, so it waits again and the run settles as `advance/1` does;
  the User retries by choosing the Niche again.
  """
  def resume(%Run{} = run) do
    reset_interrupted_steps(run)
    run |> Ecto.Changeset.change(status: :running) |> Repo.update!()

    run.id
    |> load_run_with_steps()
    |> advance_loaded_run()
  end

  defp advance_loaded_run(%Run{status: :running, steps: steps} = run) do
    case Enum.find(steps, &(Steps.auto_chained?(&1.number) and not RunStep.finished?(&1))) do
      nil -> start_queued_or_settle(run)
      %RunStep{status: :waiting} = step -> start_or_skip(run, step)
      _running_or_failed -> :ok
    end
  end

  defp advance_loaded_run(_missing_or_not_running), do: :ok

  defp start_or_skip(run, step) do
    definition = Steps.get!(step.number)

    if Steps.applies?(definition, run.mode) do
      insert_step_job(run, definition)
    else
      step
      |> RunStep.finish_changeset(%{status: :skipped, result: definition.skipped_result})
      |> Repo.update!()

      Research.broadcast_run_updated(run)
      advance(run)
    end
  end

  defp start_queued_or_settle(%Run{steps: steps} = run) do
    cond do
      Enum.any?(steps, &(&1.status == :running)) -> :ok
      queued_step = Enum.find(steps, &(&1.status == :queued)) -> insert_step_job(run, Steps.get!(queued_step.number))
      true -> settle(run)
    end
  end

  defp settle(run) do
    run
    |> Ecto.Changeset.change(status: :awaiting_choice)
    |> Repo.update!()

    Research.broadcast_run_updated(run)
  end

  defp reset_interrupted_steps(run) do
    run
    |> run_steps_query()
    |> where([run_step: run_step], run_step.number in ^@user_triggered_numbers and run_step.status == ^:running)
    |> Repo.update_all(set: [status: :queued, error: nil, started_at: nil, finished_at: nil])

    run
    |> run_steps_query()
    |> where([run_step: run_step], run_step.status in ^[:failed, :running])
    |> Repo.update_all(set: [status: :waiting, error: nil, started_at: nil, finished_at: nil])
  end

  defp insert_step_job(run, definition) do
    run
    |> step_job(definition)
    |> Oban.insert!()

    :ok
  end

  defp step_job(%Run{id: run_id}, %{worker: worker}) do
    Oban.Job.new(%{run_id: run_id},
      worker: worker,
      queue: :pipeline,
      max_attempts: @max_attempts,
      unique: [period: :infinity, fields: [:worker, :args], states: :incomplete]
    )
  end

  defp queue_step(run, number) do
    run
    |> run_steps_query()
    |> where([run_step: run_step], run_step.number == ^number)
    |> Repo.one!()
    |> RunStep.queue_changeset()
    |> Repo.update!()
  end

  defp run_steps_query(%Run{id: run_id}) do
    RunStep
    |> from(as: :run_step)
    |> where([run_step: run_step], run_step.run_id == ^run_id)
  end

  defp load_run_with_steps(run_id) do
    Run
    |> from(as: :run)
    |> where([run: run], run.id == ^run_id)
    |> preload(steps: ^RunStep.ordered_by_number())
    |> Repo.one()
  end
end
