defmodule Dirmoon.Workers.GenerateSeeds do
  @moduledoc """
  Step 1 of a Research Run: Seeds and customer questions from the description.
  """
  use Oban.Worker, queue: :pipeline, max_attempts: 3

  alias Dirmoon.Research.Seeds
  alias Dirmoon.Research.StepRunner

  @impl Oban.Worker
  def perform(job), do: StepRunner.run(job, 1, &Seeds.generate/1)
end
