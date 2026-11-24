defmodule Dirmoon.Workers.FetchVolumes do
  @moduledoc """
  Step 3 of a Research Run: Volume, CPC and Trend in the country and the city.
  """
  use Oban.Worker, queue: :pipeline, max_attempts: 3

  alias Dirmoon.Phrases.Volumes
  alias Dirmoon.Research.StepRunner

  @impl Oban.Worker
  def perform(job), do: StepRunner.run(job, 3, &Volumes.fetch/1)
end
