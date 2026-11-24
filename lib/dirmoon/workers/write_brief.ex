defmodule Dirmoon.Workers.WriteBrief do
  @moduledoc """
  Step 8 of a Research Run: write the Brief and the content of the run's
  `:writing` page. When the Step finally fails, the page is marked `:failed`
  with the reason, so choosing its Niche again writes it anew.
  """
  use Oban.Worker, queue: :pipeline, max_attempts: 3

  alias Dirmoon.Pages
  alias Dirmoon.Pages.BriefWriter
  alias Dirmoon.Research.StepRunner

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_id" => run_id}} = job) do
    case StepRunner.run(job, 8, &BriefWriter.write/1) do
      {:cancel, reason} = cancel ->
        Pages.fail_writing_pages(run_id, StepRunner.readable_reason(reason))
        cancel

      outcome ->
        outcome
    end
  end
end
