defmodule Dirmoon.Phrases.LedgerRows do
  @moduledoc """
  A keyword API request that answers with phrase rows (phrase ideas, search
  volumes), made through the run's ledger so a run never buys it twice.

  The ledger stores `%{"rows" => [row], "raw" => raw_body, "fetched_at" => iso8601_utc}`,
  where `"fetched_at"` is when the request was really bought (a replay keeps
  it) and a row is `%{"phrase", "search_volume", "cpc" (decimal string or nil),
  "currency", "trend" => [%{"year", "month", "search_volume"}]}`.
  """

  alias Dirmoon.Research.Ledger
  alias Dirmoon.Research.Run

  @doc """
  Sends `request` through `api_function` (a `Dirmoon.DataForSEO` call
  answering `{:ok, %{rows:, raw:, cost:}}`) via the run's ledger under
  `operation`.

  Returns `{:ok, %{rows: rows, fetched_at: fetched_at}}`, each row typed
  (`%{phrase:, search_volume:, cpc: Decimal | nil, currency:, trend:, fetched_at:}`)
  and stamped with the time it was bought, or the API's `{:error, reason}`.
  """
  def fetch(%Run{} = run, %{operation: operation, request: request}, api_function) when is_function(api_function, 1) do
    with {:ok, response} <-
           Ledger.fetch(run, %{service: "dataforseo", operation: operation, request: request}, fn ->
             buy(request, api_function)
           end) do
      {:ok, typed_response(response)}
    end
  end

  defp buy(request, api_function) do
    with {:ok, %{rows: rows, raw: raw, cost: cost}} <- api_function.(request) do
      fetched_at = :second |> DateTime.utc_now() |> DateTime.to_iso8601()
      {:ok, %{"rows" => Enum.map(rows, &stored_row/1), "raw" => raw, "fetched_at" => fetched_at}, cost}
    end
  end

  defp stored_row(row) do
    %{
      "phrase" => row.phrase,
      "search_volume" => row.search_volume,
      "cpc" => row.cpc && Decimal.to_string(row.cpc),
      "currency" => row.currency,
      "trend" => Enum.map(row.trend, &%{"year" => &1.year, "month" => &1.month, "search_volume" => &1.search_volume})
    }
  end

  defp typed_response(%{"rows" => stored_rows, "fetched_at" => stored_fetched_at}) do
    {:ok, fetched_at, 0} = DateTime.from_iso8601(stored_fetched_at)
    %{rows: Enum.map(stored_rows, &typed_row(&1, fetched_at)), fetched_at: fetched_at}
  end

  defp typed_row(row, fetched_at) do
    %{
      phrase: row["phrase"],
      search_volume: row["search_volume"],
      cpc: row["cpc"] && Decimal.new(row["cpc"]),
      currency: row["currency"],
      trend: Enum.map(row["trend"], &%{year: &1["year"], month: &1["month"], search_volume: &1["search_volume"]}),
      fetched_at: fetched_at
    }
  end
end
