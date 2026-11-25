defmodule Dirmoon.Workers.CheckCompetitorPrices do
  @moduledoc """
  Runs a Price Check the User started (`Dirmoon.PriceChecks.start/2`): reads
  its waiting Competitor Pages (`Dirmoon.PriceChecks.Checker.check/1`) and
  marks it done. Not a Step: it never touches the run's Steps or status.

  An error is retried by Oban; on the last attempt, or at once when the LLM
  has no key, the check is marked failed with a readable reason
  (`Dirmoon.Research.StepRunner.readable_reason/1`) and the job is
  cancelled. A check that is no longer `:checking` is left alone.
  """
  use Oban.Worker,
    queue: :pipeline,
    max_attempts: 3,
    unique: [period: :infinity, fields: [:worker, :args], states: :incomplete]

  alias Dirmoon.PriceChecks
  alias Dirmoon.PriceChecks.Checker
  alias Dirmoon.PriceChecks.PriceCheck
  alias Dirmoon.Research.StepRunner

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"price_check_id" => price_check_id}} = job) do
    case PriceChecks.get_checking(price_check_id) do
      %PriceCheck{} = price_check -> price_check |> check_safely() |> settle(%{price_check: price_check, job: job})
      nil -> :ok
    end
  end

  defp check_safely(price_check) do
    Checker.check(price_check)
  rescue
    exception -> {:error, exception}
  end

  defp settle(:ok, %{price_check: price_check}) do
    PriceChecks.finish(price_check)
    :ok
  end

  defp settle({:error, reason}, %{price_check: price_check, job: job}) do
    if job.attempt >= job.max_attempts or StepRunner.not_configured?(reason) do
      PriceChecks.fail(price_check, StepRunner.readable_reason(reason))
      {:cancel, reason}
    else
      {:error, reason}
    end
  end
end
