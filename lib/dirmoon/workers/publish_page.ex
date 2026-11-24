defmodule Dirmoon.Workers.PublishPage do
  @moduledoc """
  Step 9 of a Research Run: deploy the run's `:publishing` page. When the
  Step finally fails, the page goes back to `:ready` (or `:published`,
  keeping its earlier URL) with the reason, so it can still be edited,
  downloaded and published again.
  """
  use Oban.Worker, queue: :pipeline, max_attempts: 3

  alias Dirmoon.Pages
  alias Dirmoon.Pages.Publisher
  alias Dirmoon.Research.StepRunner

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_id" => run_id}} = job) do
    case StepRunner.run(job, 9, &Publisher.publish/1) do
      {:cancel, reason} = cancel ->
        Pages.fail_publishing_pages(run_id, StepRunner.readable_reason(reason))
        cancel

      outcome ->
        outcome
    end
  end
end
