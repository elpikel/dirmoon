defmodule Dirmoon.Workers.FilterAndGroup do
  @moduledoc """
  Step 4 of a Research Run: drop the Phrases outside the business and group
  the rest into Niches. When the Step finishes, an Existing Site run's
  Niches exist, so it enqueues the matching of the Site Scan's pages to
  them (`Dirmoon.SiteScans.enqueue_matching/1`, which never raises and
  enqueues nothing for a New Idea run); the Step's outcome is the same
  either way.
  """
  use Oban.Worker, queue: :pipeline, max_attempts: 3

  alias Dirmoon.Niches.Grouping
  alias Dirmoon.Research.StepRunner
  alias Dirmoon.SiteScans

  @impl Oban.Worker
  def perform(job), do: StepRunner.run(job, 4, &make_niches_then_enqueue_matching/1)

  defp make_niches_then_enqueue_matching(run) do
    outcome = Grouping.group(run)
    if match?({:ok, _grouped}, outcome), do: SiteScans.enqueue_matching(run)
    outcome
  end
end
