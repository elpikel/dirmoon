defmodule Dirmoon.Workers.FetchCurrentPositions do
  @moduledoc """
  Step 6 of a Research Run: the Existing Site's Current Positions from
  Search Console.
  """
  use Oban.Worker, queue: :pipeline, max_attempts: 3

  alias Dirmoon.Research.StepRunner
  alias Dirmoon.SearchConsole.Positions

  @impl Oban.Worker
  def perform(job), do: StepRunner.run(job, 6, &Positions.fetch/1)
end
