defmodule Dirmoon.Workers.ScanSite do
  @moduledoc """
  Reads the site of an Existing Site run for its Site Scan
  (`Dirmoon.SiteScans.start/1` and `retry/2` enqueue it, one job per scan)
  with `Dirmoon.SiteScans.Crawler.crawl/1`, then marks the scan done and
  enqueues the matching of its pages to the run's Niches
  (`Dirmoon.SiteScans.enqueue_matching/1`, which never raises, so the scan
  stays done whatever the enqueue does). Not a
  Step: it never touches the run's Steps or status, and runs on its own
  `site_scan` queue.

  An error, or an exception, exit or throw in the crawl, is retried by Oban; the pages
  already stored are not read again. On the last attempt the scan is marked
  failed with a readable reason
  (`Dirmoon.Research.StepRunner.readable_reason/1`) and the job is
  cancelled. Every status change is broadcast. A scan that is no longer
  `:scanning`, or is gone, is left alone.
  """
  use Oban.Worker,
    queue: :site_scan,
    max_attempts: 3,
    unique: [period: :infinity, fields: [:worker, :args], states: :incomplete]

  alias Dirmoon.Research.StepRunner
  alias Dirmoon.SiteScans
  alias Dirmoon.SiteScans.Crawler
  alias Dirmoon.SiteScans.SiteScan

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"site_scan_id" => site_scan_id}} = job) do
    case SiteScans.get_scanning(site_scan_id) do
      %SiteScan{} = site_scan -> site_scan |> crawl_safely() |> settle(%{site_scan: site_scan, job: job})
      nil -> :ok
    end
  end

  defp crawl_safely(site_scan) do
    Crawler.crawl(site_scan)
  rescue
    exception -> {:error, exception}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp settle({:ok, crawled}, %{site_scan: site_scan}) do
    SiteScans.finish(crawled, :done)
    SiteScans.enqueue_matching(site_scan.run)
  end

  defp settle({:error, reason}, %{site_scan: site_scan, job: job}) do
    if job.attempt >= job.max_attempts do
      SiteScans.finish(site_scan, {:failed, StepRunner.readable_reason(reason)})
      {:cancel, reason}
    else
      {:error, reason}
    end
  end
end
