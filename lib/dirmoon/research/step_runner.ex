defmodule Dirmoon.Research.StepRunner do
  @moduledoc """
  The bookkeeping around one Step, so each worker's `perform/1` is a one-liner:

      def perform(job), do: StepRunner.run(job, 1, &Seeds.generate/1)

  The step function gets the run and returns `{:ok, %{result: line, output: map}}`,
  `{:skip, line}`, `{:error, reason}`, or `:stopped` when it found the run no
  longer running and stopped early: the Step then waits again, without an
  error. When the run is still stopped, a resume runs the Step again. When the
  run was resumed meanwhile, the resume's job landed on this still-executing
  unique job, so this job snoozes and runs the Step again itself.
  """

  import Ecto.Query

  alias Dirmoon.Repo
  alias Dirmoon.Research
  alias Dirmoon.Research.Pipeline
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.RunStep

  @not_configured_messages %{
    llm_not_configured: "Nie wybrano dostawcy LLM",
    data_for_seo_not_configured: "Brak danych logowania DataForSEO",
    hosting_not_configured: "Brak tokenu Netlify"
  }

  @doc """
  Runs Step `number` of the job's run (`args["run_id"]`) through `step_function`.

  Returns `:ok` when the Step finished or skipped (and the pipeline advanced),
  when the run isn't running, or when the Step was already finished (it isn't
  run again), or when the step function returned `:stopped` and the run is
  still not running (the Step waits again and the pipeline doesn't advance).
  Returns `{:snooze, 1}` when the step function returned `:stopped` but the
  run is running again by then (the Step waits and this job runs it again;
  a snooze doesn't use up an attempt). Returns `{:error, reason}` for
  Oban to retry. On the last attempt,
  or when a client isn't configured, marks the Step and the run failed with a
  readable reason and returns `{:cancel, reason}` so Oban stops retrying.
  """
  def run(%Oban.Job{args: %{"run_id" => run_id}} = job, number, step_function) when is_function(step_function, 1) do
    case Repo.get(Run, run_id) do
      %Run{status: :running} = run -> run_step(%{run: run, job: job, step: fetch_step(run, number)}, step_function)
      _missing_or_not_running -> :ok
    end
  end

  @doc """
  The reason a Step failed, as shown to the User: a readable message for a
  client that isn't configured, the reason itself when it's text, and an
  "unexpected error" line for an exception or any other term.
  """
  def readable_reason(reason) when is_map_key(@not_configured_messages, reason),
    do: Map.fetch!(@not_configured_messages, reason)

  def readable_reason(reason) when is_binary(reason), do: reason
  def readable_reason(reason) when is_exception(reason), do: "Nieoczekiwany błąd: " <> Exception.message(reason)
  def readable_reason(reason), do: "Nieoczekiwany błąd: " <> inspect(reason)

  defp run_step(%{run: run, step: step} = context, step_function) do
    if RunStep.finished?(step) do
      Pipeline.advance(run)
    else
      started_step = step |> RunStep.start_changeset() |> Repo.update!()
      Research.broadcast_run_updated(run)

      run
      |> call_safely(step_function)
      |> record_outcome(%{context | step: started_step})
    end
  end

  defp call_safely(run, step_function) do
    step_function.(run)
  rescue
    exception -> {:error, exception}
  end

  defp record_outcome({:ok, %{result: result} = outcome}, context) do
    finish(context, %{status: :done, result: result, output: Map.get(outcome, :output)})
  end

  defp record_outcome({:skip, result}, context) do
    finish(context, %{status: :skipped, result: result})
  end

  defp record_outcome(:stopped, %{run: run, step: step}) do
    step |> RunStep.interrupt_changeset() |> Repo.update!()
    Research.broadcast_run_updated(run)

    if Research.running?(run), do: {:snooze, 1}, else: :ok
  end

  defp record_outcome({:error, reason}, %{job: job} = context) do
    if final_attempt?(job) or not_configured?(reason) do
      fail(context, reason)
      {:cancel, reason}
    else
      {:error, reason}
    end
  end

  defp record_outcome(unexpected_outcome, context) do
    record_outcome({:error, {:unexpected_step_outcome, unexpected_outcome}}, context)
  end

  defp finish(%{run: run, step: step}, outcome) do
    step |> RunStep.finish_changeset(outcome) |> Repo.update!()
    Research.broadcast_run_updated(run)
    Pipeline.advance(run)
  end

  defp fail(%{run: run, step: step}, reason) do
    Repo.transact(fn ->
      step |> RunStep.fail_changeset(readable_reason(reason)) |> Repo.update!()
      fail_running_run(run)
      {:ok, run}
    end)

    Research.broadcast_run_updated(run)
  end

  defp fail_running_run(%Run{id: run_id}) do
    Run
    |> from(as: :run)
    |> where([run: run], run.id == ^run_id and run.status == ^:running)
    |> Repo.update_all(set: [status: :failed, updated_at: DateTime.utc_now(:second)])
  end

  defp fetch_step(run, number) do
    Repo.get_by!(RunStep, run_id: run.id, number: number)
  end

  defp final_attempt?(%Oban.Job{attempt: attempt, max_attempts: max_attempts}), do: attempt >= max_attempts

  defp not_configured?(reason), do: Map.has_key?(@not_configured_messages, reason)
end
