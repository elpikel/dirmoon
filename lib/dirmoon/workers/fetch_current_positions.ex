defmodule Dirmoon.Workers.FetchCurrentPositions do
  @moduledoc """
  Step 6 of a Research Run: the Existing Site's Current Positions, from
  Search Console or Google's results (`Dirmoon.Phrases.CurrentPositions`).
  When the Step finishes, the Niches exist, so it enqueues the matching of
  the Site Scan's pages to them (`Dirmoon.SiteScans.enqueue_matching/1`,
  which never raises); the Step's outcome is the same either way.
  """
  use Oban.Worker, queue: :pipeline, max_attempts: 3

  alias Dirmoon.Phrases.CurrentPositions
  alias Dirmoon.Research.StepRunner
  alias Dirmoon.SiteScans

  @impl Oban.Worker
  def perform(job), do: StepRunner.run(job, 6, &fetch_then_enqueue_matching/1)

  defp fetch_then_enqueue_matching(run) do
    outcome = CurrentPositions.fetch(run)
    if finished?(outcome), do: SiteScans.enqueue_matching(run)
    outcome
  end

  defp finished?({:ok, _outcome}), do: true
  defp finished?({:skip, _line}), do: true
  defp finished?(_error_or_stopped), do: false
end
