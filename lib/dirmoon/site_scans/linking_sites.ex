defmodule Dirmoon.SiteScans.LinkingSites do
  @moduledoc """
  How many other sites link to some domains, bought for a run in one
  request (`Dirmoon.DataForSEO.linking_sites/1`) through its ledger
  (`Dirmoon.Research.Ledger`), so the run pays for it once and its cost is
  in the run's API Cost. Used by the Site Scan for the site's own domain
  and by a Price Check for its Competitor Pages' domains.

  The ledger keeps the domains sorted and once each, so the same domains
  asked in another order replay the same answer. It stores the rows with
  DataForSEO's raw answer, or, when DataForSEO refused the request itself,
  that refusal with its raw answer and cost, which is then not asked
  again. Any other failure is stored nowhere and can be asked again.
  """

  alias Dirmoon.DataForSEO
  alias Dirmoon.Research.Ledger
  alias Dirmoon.Research.Run

  @doc """
  The count of sites linking to each of `domains` (bare hosts, as stored)
  for `run`.

  Returns `{:ok, %{domain => count}}`, without a domain DataForSEO has no
  data for, `{:error, :unavailable}` when DataForSEO refused the request,
  or `{:error, reason}` (`:data_for_seo_not_configured`,
  `:not_in_demo_data`, any other failure).
  """
  def count(%Run{} = run, domains) when is_list(domains) do
    request = %{domains: domains |> Enum.uniq() |> Enum.sort()}
    paid_request = %{service: "dataforseo", operation: "linking_sites", request: request}

    case Ledger.fetch(run, paid_request, fn -> buy(request) end) do
      {:ok, %{"rows" => rows}} -> {:ok, Map.new(rows, &{&1["domain"], &1["linking_sites"]})}
      {:ok, %{"unavailable" => _message}} -> {:error, :unavailable}
      {:error, reason} -> {:error, reason}
    end
  end

  defp buy(request) do
    case DataForSEO.linking_sites(request) do
      {:ok, %{rows: rows, raw: raw, cost: cost}} ->
        {:ok, %{"rows" => rows, "raw" => raw}, cost}

      {:error, {:linking_sites_unavailable, %{message: message, raw: raw, cost: cost}}} ->
        {:ok, %{"unavailable" => message, "raw" => raw}, cost}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
