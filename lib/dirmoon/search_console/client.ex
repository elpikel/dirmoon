defmodule Dirmoon.SearchConsole.Client do
  @moduledoc """
  The seam to Google: the OAuth consent URL, the code exchange, access token
  refresh and the Search Analytics query. The adapter is chosen by
  `config :dirmoon, :search_console_adapter`: `Client.Google` when Google
  OAuth credentials are set, otherwise `Client.NotConfigured`. There is no
  demo adapter, so no Current Positions are ever made up.

  Adapters never put a client secret, code or token into an error reason.
  """

  @type authorize_request :: %{state: String.t(), redirect_uri: String.t()}
  @type exchange_request :: %{code: String.t(), redirect_uri: String.t()}
  @type tokens :: %{refresh_token: String.t(), access_token: String.t(), email: String.t()}
  @type refresh_request :: %{refresh_token: String.t()}
  @type access :: %{access_token: String.t(), expires_in: pos_integer()}
  @type query_request :: %{
          access_token: String.t(),
          site_url: String.t(),
          start_date: Date.t(),
          end_date: Date.t(),
          row_limit: pos_integer()
        }
  @type row :: %{
          query: String.t(),
          clicks: number(),
          impressions: number(),
          ctr: number(),
          position: number()
        }

  @callback authorize_url(authorize_request()) :: {:ok, String.t()} | {:error, term()}
  @callback exchange_code(exchange_request()) :: {:ok, tokens()} | {:error, :no_refresh_token | term()}
  @callback refresh_access_token(refresh_request()) :: {:ok, access()} | {:error, :invalid_grant | term()}
  @callback query(query_request()) :: {:ok, %{rows: [row()], raw: map()}} | {:error, :forbidden | term()}

  @doc "The Google consent screen URL carrying `state`, returning to `redirect_uri`."
  @spec authorize_url(authorize_request()) :: {:ok, String.t()} | {:error, term()}
  def authorize_url(request), do: adapter().authorize_url(request)

  @doc "Trades the callback's code for a refresh token, an access token and the Google email."
  @spec exchange_code(exchange_request()) :: {:ok, tokens()} | {:error, :no_refresh_token | term()}
  def exchange_code(request), do: adapter().exchange_code(request)

  @doc "A fresh access token for a stored refresh token; `:invalid_grant` when it was revoked or expired."
  @spec refresh_access_token(refresh_request()) :: {:ok, access()} | {:error, :invalid_grant | term()}
  def refresh_access_token(request), do: adapter().refresh_access_token(request)

  @doc "The property's queries with clicks, impressions, CTR and average position; `:forbidden` without access."
  @spec query(query_request()) :: {:ok, %{rows: [row()], raw: map()}} | {:error, :forbidden | term()}
  def query(request), do: adapter().query(request)

  defp adapter, do: Application.fetch_env!(:dirmoon, :search_console_adapter)
end
