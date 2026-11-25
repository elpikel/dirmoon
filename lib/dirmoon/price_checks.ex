defmodule Dirmoon.PriceChecks do
  @moduledoc """
  Price Checks: what a Niche's direct competitors charge, read on demand
  from the pages of theirs that hold Google's first page for the Niche's
  Phrases. Not a Step: the run keeps its eight Steps and its status.

  The User starts a check (`start/2`) through the Scope; the Competitor
  Pages are picked then (`competitor_pages/1`) and stored, and
  `Dirmoon.Workers.CheckCompetitorPrices` reads them
  (`Dirmoon.PriceChecks.Checker`). Subscribers to a run's price checks
  (`subscribe/1`) receive `{:price_check_updated, niche_id}` whenever a
  check of one of its Niches changes.
  """

  import Ecto.Query

  alias Dirmoon.Accounts.Scope
  alias Dirmoon.Competition.SerpAssessment
  alias Dirmoon.Niches
  alias Dirmoon.Niches.Niche
  alias Dirmoon.PriceChecks.CompetitorPage
  alias Dirmoon.PriceChecks.PriceCheck
  alias Dirmoon.Repo
  alias Dirmoon.Research
  alias Dirmoon.Research.Run
  alias Dirmoon.Workers.CheckCompetitorPrices

  @web_schemes ["http", "https"]
  @www_prefix "www."

  @doc "The most Competitor Pages one Price Check reads."
  def page_limit, do: Application.fetch_env!(:dirmoon, :price_check_page_limit)

  @doc """
  The Competitor Pages a Price Check of a Niche reads, from the Niche's
  first pages (`Dirmoon.Niches.niche_detail/2`'s `first_pages`): the results
  labelled direct competitor with an `http`/`https` address, one per domain
  (the best-placed address; `www.` doesn't make another domain), best
  Google position first, at most `page_limit/0`.

  Returns `[%{domain: String.t(), url: String.t(), google_position: integer}]`.
  """
  def competitor_pages(first_pages) when is_list(first_pages) do
    direct_competitor = SerpAssessment.direct_competitor()

    first_pages
    |> Enum.flat_map(& &1.results)
    |> Enum.filter(&(&1.page_type == direct_competitor))
    |> Enum.flat_map(&with_domain/1)
    |> Enum.sort_by(& &1.google_position)
    |> Enum.uniq_by(& &1.domain)
    |> Enum.take(page_limit())
  end

  @doc """
  The Niche's Price Check with its Competitor Pages in order, or nil. Takes
  a Niche already resolved through the Scope.
  """
  def get_for_niche(%Niche{id: niche_id}) do
    PriceCheck
    |> Repo.get_by(cluster_id: niche_id)
    |> Repo.preload(:competitor_pages)
  end

  @doc """
  The User asks for the prices of a Niche's competitors. A Niche that
  already has a check being run or done returns it and starts nothing; a
  failed check runs again for the pages not read yet. Otherwise the run's
  results must be ready (else `:run_not_ready`) and the Niche must have
  Competitor Pages (else `:no_competitors`); the check and its pages are
  stored and the worker is enqueued in one transaction, with the run locked
  so two requests never start two checks; subscribers are told once it
  commits.

  Returns `{:ok, price_check}` or
  `{:error, :not_found | :run_not_ready | :no_competitors}`.
  """
  def start(%Scope{} = scope, niche_id) do
    with %Niche{} = niche <- Niches.get_niche(scope, niche_id) || {:error, :not_found},
         {:ok, %{price_check: price_check, started?: started?}} <-
           Repo.transact(fn -> start_or_keep(niche) end) do
      if started?, do: broadcast_updated(price_check)
      {:ok, get_for_niche(niche)}
    end
  end

  @doc """
  The Price Check with the given id if it is still `:checking`, else nil.
  Called by the worker with its job's id, never with params.
  """
  def get_checking(price_check_id) when is_integer(price_check_id) do
    PriceCheck
    |> from(as: :price_check)
    |> where([price_check: price_check], price_check.id == ^price_check_id and price_check.status == ^:checking)
    |> preload([:competitor_pages, :run, :niche])
    |> Repo.one()
  end

  @doc """
  Stores what reading one Competitor Page gave:
  `%{outcome: :prices_found | :no_prices | :unreadable, offers: [map], read_url: String.t() | nil}`,
  and tells subscribers.
  """
  def record_page(%PriceCheck{} = price_check, %CompetitorPage{} = page, %{outcome: outcome} = reading) do
    page
    |> Ecto.Changeset.change(outcome: outcome, read_url: Map.get(reading, :read_url))
    |> Ecto.Changeset.put_embed(:offers, Map.get(reading, :offers, []))
    |> Repo.update!()

    broadcast_updated(price_check)
  end

  @doc "Marks the check `:done` and tells subscribers."
  def finish(%PriceCheck{} = price_check), do: settle(price_check, %{status: :done, error: nil})

  @doc "Marks the check `:failed` with a readable `reason` and tells subscribers."
  def fail(%PriceCheck{} = price_check, reason) when is_binary(reason),
    do: settle(price_check, %{status: :failed, error: reason})

  @doc "Subscribes the caller to the Price Checks of a run already resolved through the Scope."
  def subscribe(%Run{} = run), do: Phoenix.PubSub.subscribe(Dirmoon.PubSub, topic(run.id))

  defp start_or_keep(niche) do
    run = Research.lock_run!(niche.run_id)

    case Repo.get_by(PriceCheck, cluster_id: niche.id) do
      %PriceCheck{status: :failed} = failed -> restart(failed)
      %PriceCheck{} = kept -> {:ok, %{price_check: kept, started?: false}}
      nil -> create(%{run: run, niche: niche})
    end
  end

  defp restart(price_check) do
    restarted = price_check |> Ecto.Changeset.change(status: :checking, error: nil) |> Repo.update!()
    enqueue(restarted)
    {:ok, %{price_check: restarted, started?: true}}
  end

  defp create(%{run: run, niche: niche}) do
    with :ok <- ensure_results_ready(run),
         {:ok, pages} <- pages_to_read(run, niche) do
      price_check = Repo.insert!(%PriceCheck{run_id: run.id, cluster_id: niche.id, status: :checking})
      Enum.each(pages, &Repo.insert!(struct(CompetitorPage, Map.put(&1, :price_check_id, price_check.id))))
      enqueue(price_check)
      {:ok, %{price_check: price_check, started?: true}}
    end
  end

  defp ensure_results_ready(run) do
    if Run.results_ready?(run), do: :ok, else: {:error, :run_not_ready}
  end

  defp pages_to_read(run, niche) do
    case run |> Niches.niche_detail(niche) |> Map.fetch!(:first_pages) |> competitor_pages() do
      [] -> {:error, :no_competitors}
      pages -> {:ok, pages}
    end
  end

  defp enqueue(%PriceCheck{id: id}) do
    %{price_check_id: id}
    |> CheckCompetitorPrices.new()
    |> Oban.insert!()
  end

  defp settle(%PriceCheck{id: id} = price_check, changes) do
    PriceCheck
    |> from(as: :price_check)
    |> where([price_check: price_check], price_check.id == ^id)
    |> Repo.update_all(set: [status: changes.status, error: changes.error, updated_at: DateTime.utc_now(:second)])

    broadcast_updated(price_check)
  end

  defp with_domain(%{url: url, position: position}) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in @web_schemes and is_binary(host) and host != "" ->
        [
          %{
            domain: host |> String.downcase() |> String.replace_prefix(@www_prefix, ""),
            url: url,
            google_position: position
          }
        ]

      _not_a_web_address ->
        []
    end
  end

  defp with_domain(_without_address), do: []

  defp broadcast_updated(%PriceCheck{run_id: run_id, cluster_id: niche_id}) do
    Phoenix.PubSub.broadcast(Dirmoon.PubSub, topic(run_id), {:price_check_updated, niche_id})
  end

  defp topic(run_id), do: "price_checks:#{run_id}"
end
