defmodule Dirmoon.Workers.ScoreNiches do
  @moduledoc """
  Step 7 of a Research Run: score the run's Niches. After it the run awaits
  a Niche choice.
  """
  use Oban.Worker, queue: :pipeline, max_attempts: 3

  alias Dirmoon.Niches.ScoreStep
  alias Dirmoon.Research.StepRunner

  @impl Oban.Worker
  def perform(job), do: StepRunner.run(job, 7, &ScoreStep.score/1)
end
