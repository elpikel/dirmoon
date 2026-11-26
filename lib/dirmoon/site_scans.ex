defmodule Dirmoon.SiteScans do
  @moduledoc """
  Site Scans: reading an Existing Site's own pages beside Steps 1–7. Not a
  Step: the run keeps its eight Steps and its status, so a site that can't
  be read never fails the research.

  `Dirmoon.Research.start_run/2` starts the scan (`start/1`) in the run's
  transaction and `Dirmoon.Workers.ScanSite` reads the site
  (`Dirmoon.SiteScans.Crawler`), storing each Scanned Page as it is read
  (`record_pages/2`) and the site-level facts on the scan (`put_facts/2`),
  then marks it done or failed (`finish/2`); the User runs a failed or
  stale scan again with `retry/2`. Once the scan is done and the run has
  its Niches, `Dirmoon.Workers.MatchSitePages` matches the Scanned Pages
  to them (`enqueue_matching/1`, `Dirmoon.SiteScans.Matching`). The scan and
  its Scanned Pages live in their own per-run tables (`site_scans`,
  `scanned_pages`), never in the shared market tables (ADR-0002).
  Subscribers to a run's scan (`subscribe/1`) receive
  `{:site_scan_updated, run_id}` whenever it changes.

  Whatever the crawl read, the facts written are cleaned on the way in
  (`Dirmoon.JsonSafe.encode/1`), so a byte a site sent can never stop a
  scan from being stored. A scan is loaded with at most `page_limit/0`
  Scanned Pages, each with facts under 175 KB (`Dirmoon.SiteScans.Crawler`),
  so loading one stays under 9 MB.
  """

  import Ecto.Query

  alias Dirmoon.Accounts.Scope
  alias Dirmoon.JsonSafe
  alias Dirmoon.Niches
  alias Dirmoon.Phrases
  alias Dirmoon.Repo
  alias Dirmoon.Research
  alias Dirmoon.Research.Run
  alias Dirmoon.SiteScans.Findings
  alias Dirmoon.SiteScans.Findings.SitePages
  alias Dirmoon.SiteScans.ScannedPage
  alias Dirmoon.SiteScans.SiteScan
  alias Dirmoon.Workers.MatchSitePages
  alias Dirmoon.Workers.ScanSite

  require Logger

  @doc "The most Scanned Pages one Site Scan reads."
  def page_limit, do: Application.fetch_env!(:dirmoon, :site_scan_page_limit)

  @doc """
  Starts the Site Scan of an Existing Site run: stores it `:scanning` and
  enqueues its job. Called inside `Dirmoon.Research.start_run/2`'s
  transaction, so the run, its scan and the job are stored together.

  Returns `{:ok, site_scan}`.
  """
  def start(%Run{id: run_id, mode: :existing_site}) do
    site_scan = Repo.insert!(%SiteScan{run_id: run_id, status: :scanning})
    enqueue(site_scan)
    {:ok, site_scan}
  end

  @doc """
  The User runs the Site Scan of their run again when it failed or is
  stale (`stale?/1`): it is `:scanning` without its error, its job is
  enqueued, and subscribers are told. The pages already read are kept and
  not read again. Any other scan is returned as it is and nothing is
  enqueued.

  A stale scan's job is one a restart left `executing` for good, so the new
  job is enqueued past it: only a waiting or retrying job of the scan stops
  it. The staleness is the guard against two live crawls, since a crawl at
  work stores something every few seconds.

  Returns `{:ok, site_scan}`, or `{:error, :not_found}` for a run outside
  the Scope's Account, a missing run or a run without a scan.
  """
  def retry(%Scope{} = scope, run_id) do
    case get_for_run(scope, run_id) do
      %SiteScan{status: :failed} = site_scan -> {:ok, restart(site_scan)}
      %SiteScan{} = site_scan -> {:ok, if(stale?(site_scan), do: restart(site_scan), else: site_scan)}
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Whether the scan says `:scanning` but has stored nothing for longer than
  `site_scan_stale_after_minutes`: its job was lost (say, to a restart), so
  the User may run it again (`retry/2`). A crawl at work bumps the scan's
  `updated_at` with every batch of pages and every fact it stores.
  """
  def stale?(%SiteScan{status: :scanning, updated_at: %DateTime{} = updated_at}) do
    stale_before =
      DateTime.shift(DateTime.utc_now(), minute: -Application.fetch_env!(:dirmoon, :site_scan_stale_after_minutes))

    DateTime.before?(updated_at, stale_before)
  end

  def stale?(%SiteScan{}), do: false

  @doc """
  Enqueues the matching of an Existing Site run's Scanned Pages to its
  Niches (`Dirmoon.Workers.MatchSitePages`), which does nothing until both
  the scan is done and the Niches exist. Called when either side finishes:
  the scan, Step 4 (which makes the Niches) and Step 6. A New Idea run has
  no scan: nothing is enqueued.

  Always returns `:ok`: the callers' own outcome (Step 4, Step 6, the scan) must
  never depend on it, so an enqueue that raises, exits or throws is logged
  once as a warning, naming only the run and the kind of failure, and the
  pages stay unmatched until the other side enqueues again.
  """
  def enqueue_matching(%Run{id: run_id, mode: :existing_site}) do
    %{run_id: run_id}
    |> MatchSitePages.new()
    |> Oban.insert!()

    :ok
  catch
    kind, _reason -> log_matching_not_enqueued(run_id, kind)
  end

  def enqueue_matching(%Run{}), do: :ok

  @doc """
  The Site Scan of the run with the given id, with its run and the run's
  Steps and its first `page_limit/0` Scanned Pages in read order, or nil.
  Called by the matching worker with its job's run id, never with params.
  """
  def get_for_matching(run_id) when is_integer(run_id) do
    SiteScan
    |> from(as: :site_scan)
    |> where([site_scan: site_scan], site_scan.run_id == ^run_id)
    |> preload(run: :steps, scanned_pages: ^first_pages_read())
    |> Repo.one()
  end

  @doc """
  The Site Scan of the Scope's Account's run with the given id, with its
  first `page_limit/0` Scanned Pages in read order, or nil for a run outside the Scope's
  Account, a missing run or a run without a scan.
  """
  def get_for_run(%Scope{} = scope, run_id) do
    case Research.get_run(scope, run_id) do
      %Run{} = run -> scan_of(run)
      nil -> nil
    end
  end

  @doc """
  What the "Your site" screen shows of the Scope's Account's run with the
  given id: the run, its Site Scan and the Findings worked out from what the
  scan stored (`Dirmoon.SiteScans.Findings.build/1`, with the run's Niche
  summaries, its kept Phrases and any other Phrase the site ranks with, and
  the page limit). A scan still `:scanning` comes without its Scanned Pages
  and with no Findings: only its status and `pages_read`, so following a
  scan at work stays cheap; the Findings come once it ends.

  Returns `{:ok, %{run:, scan:, findings:}}`, with `scan: nil` and no
  Findings for a run without a scan (a New Idea run), or
  `{:error, :not_found}` for a run outside the Scope's Account or a missing
  run.
  """
  def report(%Scope{} = scope, run_id) do
    case Research.get_run(scope, run_id) do
      %Run{} = run -> {:ok, run |> status_of() |> report_of(run)}
      nil -> {:error, :not_found}
    end
  end

  @doc """
  The Site Scan of a run already resolved through the Scope, without its
  Scanned Pages, or nil when the run has none (a New Idea run).
  """
  def status_of(%Run{id: run_id}), do: Repo.get_by(SiteScan, run_id: run_id)

  @doc """
  The addresses of the site's own Scanned Pages
  (`Dirmoon.SiteScans.Findings.SitePages.own_pages/1`, the rule the Findings
  use) matched to each Niche of a run already resolved through the Scope,
  in read order, once the matching is done; nil while it isn't (or the run has no scan), so a screen shows
  nothing rather than "no page". One query.

  Returns `%{niche_id => [address]}` or nil.
  """
  def matched_pages_by_niche(%Run{id: run_id}) do
    SiteScan
    |> from(as: :site_scan)
    |> where([site_scan: site_scan], site_scan.run_id == ^run_id)
    |> where([site_scan: site_scan], fragment("(?->'matching'->>'done') = 'true'", site_scan.facts))
    |> join(:left, [site_scan: site_scan], scanned_page in assoc(site_scan, :scanned_pages),
      as: :scanned_page,
      on: not is_nil(scanned_page.cluster_id)
    )
    |> order_by([scanned_page: scanned_page], asc: scanned_page.position, asc: scanned_page.id)
    |> select([scanned_page: scanned_page], scanned_page)
    |> Repo.all()
    |> matched_addresses()
  end

  @doc """
  The site's side of a Niche's comparison with its Competitor Pages, for a
  run already resolved through the Scope and one of its Niches: nil when
  the run has no scan (a New Idea run); else
  `%{scan_status: :scanning | :done | :failed, matched?: boolean,
  pages: [%ScannedPage{}], linking_sites: non_neg_integer() | nil}`.
  `matched?` says the matching is done; `pages` are then the site's own
  Scanned Pages matched to the Niche (`SitePages.own_pages/1`, the rule
  `matched_pages_by_niche/1` uses), in read order, and empty until it is
  done. `linking_sites` is the scan's count of sites linking to the site,
  nil when unknown. At most two queries.
  """
  def niche_comparison(%Run{} = run, niche_id) do
    case status_of(run) do
      %SiteScan{} = site_scan ->
        matched? = matching_done?(site_scan)

        %{
          scan_status: site_scan.status,
          matched?: matched?,
          pages: if(matched?, do: matched_pages(site_scan, niche_id), else: []),
          linking_sites: linking_sites_count(site_scan.facts)
        }

      nil ->
        nil
    end
  end

  @doc """
  The Site Scan with the given id if it is still `:scanning`, with its run
  and its first `page_limit/0` Scanned Pages in read order, else nil. Called by the worker with
  its job's id, never with params.
  """
  def get_scanning(site_scan_id) when is_integer(site_scan_id) do
    SiteScan
    |> from(as: :site_scan)
    |> where([site_scan: site_scan], site_scan.id == ^site_scan_id and site_scan.status == ^:scanning)
    |> preload([:run, scanned_pages: ^first_pages_read()])
    |> Repo.one()
  end

  @doc """
  Stores Scanned Pages just read (`%{url:, http_status:, facts:, position:}`
  each), sets the scan's `pages_read` to the number it now holds, and tells
  subscribers. Returns the updated scan.
  """
  def record_pages(%SiteScan{id: site_scan_id} = site_scan, pages) when is_list(pages) do
    {:ok, recorded} =
      Repo.transact(fn ->
        Enum.each(pages, fn page ->
          ScannedPage
          |> struct(%{page | facts: JsonSafe.encode(page.facts)})
          |> Map.put(:site_scan_id, site_scan_id)
          |> Repo.insert!()
        end)

        pages_read = site_scan_id |> scanned_pages_of() |> Repo.aggregate(:count)

        {:ok, site_scan |> Ecto.Changeset.change(pages_read: pages_read) |> Repo.update!()}
      end)

    broadcast_updated(recorded)
    recorded
  end

  @doc """
  Stores site-level facts on the scan, next to those it holds (a fact with
  the same key is replaced), and bumps its `updated_at` even when nothing
  changed, so a crawl at work never looks stale. Returns the updated scan.
  """
  def put_facts(%SiteScan{facts: facts} = site_scan, new_facts) when is_map(new_facts) do
    site_scan
    |> Ecto.Changeset.change(facts: Map.merge(facts, JsonSafe.encode(new_facts)))
    |> Repo.update!(force: true)
  end

  @doc """
  Stores an outcome of matching the scan's pages to Niches
  (`Dirmoon.SiteScans.Matching`) in one transaction: every Scanned Page of
  the scan loses its Niche, the pages in `niche_ids_by_page`
  (`%{scanned_page_id => niche_id}`) get theirs, and `matching` is stored
  as the scan's `"matching"` fact. Subscribers are told once it commits.
  Returns the updated scan.
  """
  def store_matches(%SiteScan{id: site_scan_id} = site_scan, %{niche_ids_by_page: niche_ids_by_page, matching: matching})
      when is_map(niche_ids_by_page) and is_map(matching) do
    {:ok, stored} =
      Repo.transact(fn ->
        site_scan_id
        |> scanned_pages_of()
        |> Repo.update_all(set: [cluster_id: nil])

        niche_ids_by_page
        |> Enum.group_by(fn {_page_id, niche_id} -> niche_id end, fn {page_id, _niche_id} -> page_id end)
        |> Enum.each(fn {niche_id, page_ids} ->
          site_scan_id
          |> scanned_pages_of()
          |> where([scanned_page: scanned_page], scanned_page.id in ^page_ids)
          |> Repo.update_all(set: [cluster_id: niche_id])
        end)

        {:ok, put_facts(site_scan, %{"matching" => matching})}
      end)

    broadcast_updated(stored)
    stored
  end

  @doc """
  Ends the scan: `:done`, or `{:failed, reason}` with a readable reason,
  and tells subscribers. Returns the updated scan.
  """
  def finish(%SiteScan{} = site_scan, :done), do: settle(site_scan, %{status: :done, error: nil})

  def finish(%SiteScan{} = site_scan, {:failed, reason}) when is_binary(reason),
    do: settle(site_scan, %{status: :failed, error: reason})

  @doc "Subscribes the caller to the Site Scan of a run already resolved through the Scope."
  def subscribe(%Run{id: run_id}), do: Phoenix.PubSub.subscribe(Dirmoon.PubSub, topic(run_id))

  @doc "Tells subscribers that the scan changed: `{:site_scan_updated, run_id}`."
  def broadcast_updated(%SiteScan{run_id: run_id}) do
    Phoenix.PubSub.broadcast(Dirmoon.PubSub, topic(run_id), {:site_scan_updated, run_id})
  end

  defp report_of(nil, run), do: %{run: run, scan: nil, findings: []}

  defp report_of(%SiteScan{status: :scanning} = scan, run), do: %{run: run, scan: scan, findings: []}

  defp report_of(%SiteScan{} = status, run) do
    scan = Repo.preload(status, scanned_pages: first_pages_read())

    findings =
      Findings.build(%{
        scan: scan,
        niches: Niches.list_summaries(run),
        phrases: Phrases.list_for_run(run, %{kept_or_ranked: true}),
        page_limit: page_limit()
      })

    %{run: run, scan: scan, findings: findings}
  end

  defp matched_addresses([]), do: nil

  defp matched_addresses(pages) do
    pages
    |> Enum.reject(&is_nil/1)
    |> SitePages.own_pages()
    |> Enum.group_by(& &1.cluster_id, & &1.url)
  end

  defp log_matching_not_enqueued(run_id, kind) do
    Logger.warning("The matching of the site's pages was not enqueued for run #{inspect(run_id)}: #{kind}")
    :ok
  end

  defp scan_of(%Run{} = run) do
    run
    |> status_of()
    |> Repo.preload(scanned_pages: first_pages_read())
  end

  defp scanned_pages_of(site_scan_id) do
    ScannedPage
    |> from(as: :scanned_page)
    |> where([scanned_page: scanned_page], scanned_page.site_scan_id == ^site_scan_id)
  end

  defp matching_done?(%SiteScan{facts: %{"matching" => %{"done" => true}}}), do: true
  defp matching_done?(%SiteScan{}), do: false

  defp matched_pages(%SiteScan{id: site_scan_id}, niche_id) do
    ScannedPage
    |> from(as: :scanned_page)
    |> where(
      [scanned_page: scanned_page],
      scanned_page.site_scan_id == ^site_scan_id and scanned_page.cluster_id == ^niche_id
    )
    |> order_by([scanned_page: scanned_page], asc: scanned_page.position, asc: scanned_page.id)
    |> Repo.all()
    |> SitePages.own_pages()
  end

  defp linking_sites_count(%{"linking_sites" => %{"checked" => true, "count" => count}})
       when is_integer(count) and count >= 0, do: count

  defp linking_sites_count(_facts), do: nil

  defp first_pages_read do
    ScannedPage
    |> from(as: :scanned_page)
    |> order_by([scanned_page: scanned_page], asc: scanned_page.position, asc: scanned_page.id)
    |> limit(^page_limit())
  end

  defp restart(site_scan) do
    {:ok, restarted} =
      Repo.transact(fn ->
        restarted =
          site_scan
          |> Ecto.Changeset.change(status: :scanning, error: nil)
          |> Repo.update!(force: true)

        enqueue_past_executing(restarted)
        {:ok, restarted}
      end)

    broadcast_updated(restarted)
    restarted
  end

  defp settle(site_scan, changes) do
    settled = site_scan |> Ecto.Changeset.change(changes) |> Repo.update!()
    broadcast_updated(settled)
    settled
  end

  defp enqueue(%SiteScan{id: site_scan_id}) do
    %{site_scan_id: site_scan_id}
    |> ScanSite.new()
    |> Oban.insert!()
  end

  defp enqueue_past_executing(%SiteScan{id: site_scan_id}) do
    %{site_scan_id: site_scan_id}
    |> ScanSite.new(unique: [period: :infinity, fields: [:worker, :args], states: waiting_states()])
    |> Oban.insert!()
  end

  defp waiting_states, do: Oban.Job.unique_states(:incomplete) -- [:executing]

  defp topic(run_id), do: "site_scans:#{run_id}"
end
