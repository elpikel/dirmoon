defmodule Dirmoon.SearchConsole.Positions do
  @moduledoc """
  Search Console as a source of Current Positions for Step 6: the domain
  property's queries of the last 90 days, read with the run's Account's
  Connection. Search Console is free, so nothing goes through the ledger;
  the access token lives only for the request and is never stored.
  """

  alias Dirmoon.Research.Run
  alias Dirmoon.SearchConsole
  alias Dirmoon.SearchConsole.Client
  alias Dirmoon.WebPage.HostName

  @window_days 90
  @row_limit 5000
  @not_connected "Search Console is not connected"
  @reconnect "The Search Console connection expired, connect again"
  @not_configured "Search Console is not configured"
  @access_token_rejected "Search Console rejected the access token"

  @doc """
  The run's domain property's queries of the last #{@window_days} days, at
  most #{@row_limit}.

  Returns `{:ok, %{rows: [%{query:, clicks:, impressions:, ctr:, position:}],
  window: %{start_date:, end_date:}}}`; `{:unavailable, line}` when Search
  Console can't answer for this run (no Connection, a Connection that needs
  a reconnect, a property the Google user can't access, no credentials); or
  `{:error, reason}` for a failure worth retrying.
  """
  def rows(%Run{} = run) do
    window = window(Date.utc_today())

    with {:ok, connection} <- connection(run),
         {:ok, access_token} <- access_token(connection),
         {:ok, rows} <- query(run, %{access_token: access_token, window: window}) do
      {:ok, %{rows: rows, window: window}}
    end
  end

  defp window(today), do: %{start_date: Date.add(today, -@window_days), end_date: Date.add(today, -1)}

  defp connection(run) do
    case SearchConsole.connection_for_run(run) do
      nil -> {:unavailable, @not_connected}
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
      {:error, :undecryptable_refresh_token} -> {:unavailable, @reconnect}
    end
  end

  defp refresh_access_token(refresh_token) do
    case Client.refresh_access_token(%{refresh_token: refresh_token}) do
      {:ok, access} -> {:ok, access}
      {:error, :invalid_grant} -> {:unavailable, @reconnect}
      {:error, :search_console_not_configured} -> {:unavailable, @not_configured}
      {:error, reason} -> {:error, reason}
    end
  end

  defp query(run, %{access_token: access_token, window: window}) do
    request =
      Map.merge(window, %{
        access_token: access_token,
        site_url: "sc-domain:" <> Run.ascii_domain(run),
        row_limit: @row_limit
      })

    case Client.query(request) do
      {:ok, %{rows: rows}} -> {:ok, Enum.take(rows, @row_limit)}
      {:error, :forbidden} -> {:unavailable, "No access to #{HostName.to_unicode(run.domain)} in Search Console"}
      {:error, :unauthorized} -> {:error, @access_token_rejected}
      {:error, :search_console_not_configured} -> {:unavailable, @not_configured}
      {:error, reason} -> {:error, reason}
    end
  end
end
