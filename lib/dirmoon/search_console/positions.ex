defmodule Dirmoon.SearchConsole.Positions do
  @moduledoc """
  Step 6: the Existing Site's Current Positions. Queries Search Console for
  the domain property's queries of the last 90 days with the run's
  Account's Connection, keeps the rows in the Step output (Search Console
  data stays per run, ADR-0002) and sets the Current Position of the run's
  Phrases. Search Console is free, so nothing goes through the ledger; the
  access token lives only for the request and is never stored.
  """

  alias Dirmoon.Format
  alias Dirmoon.Phrases
  alias Dirmoon.Research.Run
  alias Dirmoon.SearchConsole
  alias Dirmoon.SearchConsole.Client

  @window_days 90
  @row_limit 5000
  @new_idea_result "New idea, no site yet"
  @not_connected_result "Search Console is not connected"
  @reconnect_result "The Search Console connection expired, connect again"
  @not_configured_result "Search Console is not configured"
  @no_data_result "Search Console has no data for this domain"
  @access_token_rejected "Search Console rejected the access token"
  @phrase_forms %{one: "phrase", other: "phrases"}

  @doc """
  Fetches the run's Current Positions.

  Returns `{:ok, %{result: "N phrases at positions 8–20", output: output}}` with
  `output` `%{"rows" => [%{"query", "clicks", "impressions", "ctr", "position"}],
  "matched", "quick_wins", "start_date", "end_date"}`; `{:skip, line}` for a
  New Idea run, an Account without a Connection, a Connection that needs a
  reconnect, a property the Google user can't access or Search Console
  without credentials; or `{:error, reason}` to retry.
  """
  def fetch(%Run{mode: :new_idea}), do: {:skip, @new_idea_result}

  def fetch(%Run{} = run) do
    window = window(Date.utc_today())

    with {:ok, connection} <- connection(run),
         {:ok, access_token} <- access_token(connection),
         {:ok, rows} <- query(run, %{access_token: access_token, window: window}),
         {:ok, counts} <- Phrases.store_current_positions(run, rows) do
      {:ok, %{result: result_line(rows, counts), output: output(rows, counts, window)}}
    end
  end

  defp window(today), do: %{start_date: Date.add(today, -@window_days), end_date: Date.add(today, -1)}

  defp connection(run) do
    case SearchConsole.connection_for_run(run) do
      nil -> {:skip, @not_connected_result}
      connection -> {:ok, connection}
    end
  end

  defp access_token(connection) do
    with {:ok, refresh_token} <- refresh_token(connection),
         {:ok, %{access_token: access_token}} <- refresh_access_token(refresh_token) do
      {:ok, access_token}
    end
  end

  defp refresh_token(connection) do
    case SearchConsole.refresh_token(connection) do
      {:ok, refresh_token} -> {:ok, refresh_token}
      {:error, :undecryptable_refresh_token} -> {:skip, @reconnect_result}
    end
  end

  defp refresh_access_token(refresh_token) do
    case Client.refresh_access_token(%{refresh_token: refresh_token}) do
      {:ok, access} -> {:ok, access}
      {:error, :invalid_grant} -> {:skip, @reconnect_result}
      {:error, :search_console_not_configured} -> {:skip, @not_configured_result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp query(run, %{access_token: access_token, window: window}) do
    request =
      Map.merge(window, %{access_token: access_token, site_url: "sc-domain:" <> run.domain, row_limit: @row_limit})

    case Client.query(request) do
      {:ok, %{rows: rows}} -> {:ok, Enum.take(rows, @row_limit)}
      {:error, :forbidden} -> {:skip, "No access to #{run.domain} in Search Console"}
      {:error, :unauthorized} -> {:error, @access_token_rejected}
      {:error, :search_console_not_configured} -> {:skip, @not_configured_result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp result_line([], _counts), do: @no_data_result

  defp result_line(_rows, %{quick_wins: quick_wins}) do
    range = Phrases.quick_win_range()
    "#{quick_wins} #{Format.plural(quick_wins, @phrase_forms)} at positions #{range.first}–#{range.last}"
  end

  defp output(rows, %{matched: matched, quick_wins: quick_wins}, %{start_date: start_date, end_date: end_date}) do
    %{
      "rows" => Enum.map(rows, &stored_row/1),
      "matched" => matched,
      "quick_wins" => quick_wins,
      "start_date" => Date.to_iso8601(start_date),
      "end_date" => Date.to_iso8601(end_date)
    }
  end

  defp stored_row(row) do
    %{
      "query" => row.query,
      "clicks" => row.clicks,
      "impressions" => row.impressions,
      "ctr" => row.ctr,
      "position" => row.position
    }
  end
end
