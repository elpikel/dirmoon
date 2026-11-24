defmodule Dirmoon.Workers.ExpandPhrases do
  @moduledoc """
  Step 2 of a Research Run: Expansion of the Seeds into real Phrases.
  """
  use Oban.Worker, queue: :pipeline, max_attempts: 3

  alias Dirmoon.Phrases.Expansion
  alias Dirmoon.Research.StepRunner

  @impl Oban.Worker
  def perform(job), do: StepRunner.run(job, 2, &Expansion.expand/1)
end
