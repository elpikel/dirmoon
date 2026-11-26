defmodule Dirmoon.Workers.MatchSitePages do
  @moduledoc """
  Matches an Existing Site run's Scanned Pages to its Niches
  (`Dirmoon.SiteScans.Matching`). Enqueued by
  `Dirmoon.SiteScans.enqueue_matching/1` when either side finishes: the
  Site Scan (`Dirmoon.Workers.ScanSite`), Step 4, which makes the Niches
  (`Dirmoon.Workers.FilterAndGroup`), and Step 6
  (`Dirmoon.Workers.FetchCurrentPositions`). Step 4 enqueues it too so a
  run resumed after its scan finished gets its pages matched even when
  Step 5 or 6 then fails for good.

  One job per run at a time: the job is unique per run in every incomplete
  state, running included, so a trigger while one waits or runs adds
  nothing. A job that finds a side not ready yet
  (`Dirmoon.SiteScans.Matching.readiness/1`) snoozes for
  20 seconds and looks again, so no trigger is ever lost; a snooze
  doesn't use up an attempt. It stops waiting, storing nothing, when the
  pages can never be matched (the scan failed, the run is gone, or it
  stopped or failed before Step 4 made its Niches); a run that has its
  Niches waits for its scan whatever the run's status, awaiting the owner's
  choice included. It stores the matching as `"not_ready"` once it has waited
  30 minutes since it was enqueued.

  No database transaction is held across the LLM request: the paid answer is
  stored in the run's ledger first (`Dirmoon.Research.Ledger.fetch/3`), then
  the matches in their own transaction, so when storing them fails the retry
  replays the answer instead of paying again.

  An LLM error, or an exception, exit or throw, is retried by Oban; on the
  last attempt the matching is stored as failed and the job is cancelled.
  It never changes the run's or the scan's status.
  """
  use Oban.Worker,
    queue: :site_scan,
    max_attempts: 3,
    unique: [period: :infinity, fields: [:worker, :args], states: :incomplete]

  alias Dirmoon.SiteScans
  alias Dirmoon.SiteScans.Matching
  alias Dirmoon.SiteScans.SiteScan

  @wait_seconds 20
  @longest_wait_minutes 30

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_id" => run_id}} = job) do
    case SiteScans.get_for_matching(run_id) do
      %SiteScan{} = site_scan -> site_scan |> Matching.readiness() |> act(%{site_scan: site_scan, job: job})
      nil -> :ok
    end
  end

  defp act(:ready, %{site_scan: site_scan} = context), do: site_scan |> match_safely() |> settle(context)
  defp act(:never, _context), do: :ok

  defp act(:waiting, %{site_scan: site_scan, job: job}) do
    if waited_too_long?(job) do
      Matching.record_not_ready(site_scan)
      :ok
    else
      {:snooze, @wait_seconds}
    end
  end

  defp waited_too_long?(%Oban.Job{inserted_at: inserted_at}),
    do: DateTime.diff(DateTime.utc_now(), inserted_at, :minute) >= @longest_wait_minutes

  defp match_safely(site_scan) do
    Matching.match(site_scan)
  rescue
    exception -> {:error, exception}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp settle({:ok, _site_scan}, _context), do: :ok

  defp settle({:error, reason}, %{site_scan: site_scan, job: job}) do
    if job.attempt >= job.max_attempts do
      Matching.record_failure(site_scan)
      {:cancel, reason}
    else
      {:error, reason}
    end
  end
end
