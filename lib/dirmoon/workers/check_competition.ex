defmodule Dirmoon.Workers.CheckCompetition do
  @moduledoc """
  Step 5 of a Research Run: who holds Google's top 10 for the run's best
  Phrases.
  """
  use Oban.Worker, queue: :pipeline, max_attempts: 3

  alias Dirmoon.Competition.Check
  alias Dirmoon.Research.StepRunner

  @impl Oban.Worker
  def perform(job), do: StepRunner.run(job, 5, &Check.check/1)
end
