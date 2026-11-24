defmodule Dirmoon.SearchConsole.Client.Demo do
  @moduledoc """
  The Search Console client for development without Google credentials. The
  consent screen is skipped: the authorization URL is our own callback with
  code `demo`. Tokens are fake, the email is `demo@example.com`, and a query
  returns 40 synthetic "demo fraza N" rows, the same for the same property,
  holding every position from 1 to 40 once.
  """

  @behaviour Dirmoon.SearchConsole.Client

  alias Dirmoon.SearchConsole.Client

  @demo_email "demo@example.com"
  @demo_refresh_token "demo-refresh-token"
  @demo_access_token "demo-access-token"
  @access_token_lifetime 3600
  @row_count 40

  @impl Client
  def authorize_url(%{state: state, redirect_uri: redirect_uri}) do
    {:ok, redirect_uri <> "?" <> URI.encode_query(code: "demo", state: state)}
  end

  @impl Client
  def exchange_code(%{code: _code, redirect_uri: _redirect_uri}) do
    {:ok, %{refresh_token: @demo_refresh_token, access_token: @demo_access_token, email: @demo_email}}
  end

  @impl Client
  def refresh_access_token(%{refresh_token: _refresh_token}) do
    {:ok, %{access_token: @demo_access_token, expires_in: @access_token_lifetime}}
  end

  @impl Client
  def query(%{site_url: site_url}) do
    offset = :erlang.phash2(site_url, @row_count)

    {:ok,
     %{rows: Enum.map(1..@row_count, &row(%{site_url: site_url, number: &1, offset: offset})), raw: %{"demo" => true}}}
  end

  defp row(%{site_url: site_url, number: number, offset: offset}) do
    impressions = 10 + :erlang.phash2({site_url, number, :impressions}, 990)
    clicks = :erlang.phash2({site_url, number, :clicks}, div(impressions, 10) + 1)

    %{
      query: "demo fraza #{number}",
      clicks: clicks,
      impressions: impressions,
      ctr: clicks / impressions,
      position: rem(number + offset, @row_count) + 1 + :erlang.phash2({site_url, number, :position}, 10) / 10
    }
  end
end
