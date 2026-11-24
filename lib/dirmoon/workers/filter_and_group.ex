defmodule Dirmoon.Workers.FilterAndGroup do
  @moduledoc """
  Step 4 of a Research Run: drop the Phrases outside the business and group
  the rest into Niches.
  """
  use Oban.Worker, queue: :pipeline, max_attempts: 3

  alias Dirmoon.Niches.Grouping
  alias Dirmoon.Research.StepRunner

  @impl Oban.Worker
  def perform(job), do: StepRunner.run(job, 4, &Grouping.group/1)
end
