defmodule Dirmoon.SearchConsole.Client.Google do
  @moduledoc """
  The Google adapter: OAuth 2.0 web server flow and Search Console's
  `searchAnalytics.query` over HTTP (Req).

  Configured by `config :dirmoon, Dirmoon.SearchConsole.Client.Google` with
  `client_id`, `client_secret` and extra `req_options`. The client secret,
  codes and tokens travel only in request bodies and the bearer header; error
  reasons carry Google's error code or message, never them.

  The Google email comes from the `id_token` of the code exchange, trusted
  without signature validation because it arrives straight from Google's
  token endpoint over TLS with client-secret authentication.
  """

  @behaviour Dirmoon.SearchConsole.Client

  alias Dirmoon.SearchConsole.Client

  @authorize_url "https://accounts.google.com/o/oauth2/v2/auth"
  @token_url "https://oauth2.googleapis.com/token"
  @search_console_url "https://searchconsole.googleapis.com/webmasters/v3/sites"
  @search_console_scope "https://www.googleapis.com/auth/webmasters.readonly"
  @scopes "openid email #{@search_console_scope}"

  @impl Client
  def authorize_url(%{state: state, redirect_uri: redirect_uri}) do
    case Keyword.get(config(), :client_id) do
      client_id when is_binary(client_id) ->
        query =
          URI.encode_query(
            [
              client_id: client_id,
              redirect_uri: redirect_uri,
              response_type: "code",
              scope: @scopes,
              access_type: "offline",
              prompt: "consent",
              state: state
            ],
            :rfc3986
          )

        {:ok, @authorize_url <> "?" <> query}

      _missing ->
        {:error, :search_console_not_configured}
    end
  end

  @impl Client
  def exchange_code(%{code: code, redirect_uri: redirect_uri}) do
    with {:ok, body} <- post_token(code: code, redirect_uri: redirect_uri, grant_type: "authorization_code"),
         {:ok, access_token} <- fetch_access_token(body),
         :ok <- ensure_search_console_scope(body),
         {:ok, refresh_token} <- fetch_refresh_token(body),
         {:ok, email} <- id_token_email(body) do
      {:ok, %{refresh_token: refresh_token, access_token: access_token, email: email}}
    end
  end

  @impl Client
  def refresh_access_token(%{refresh_token: refresh_token}) do
    with {:ok, body} <- post_token(refresh_token: refresh_token, grant_type: "refresh_token"),
         {:ok, access_token} <- fetch_access_token(body) do
      {:ok, %{access_token: access_token, expires_in: body["expires_in"]}}
    end
  end

  @impl Client
  def query(%{
        access_token: access_token,
        site_url: site_url,
        start_date: start_date,
        end_date: end_date,
        row_limit: row_limit
      }) do
    [
      method: :post,
      url: "#{@search_console_url}/#{URI.encode(site_url, &URI.char_unreserved?/1)}/searchAnalytics/query",
      auth: {:bearer, access_token},
      json: %{
        startDate: Date.to_iso8601(start_date),
        endDate: Date.to_iso8601(end_date),
        dimensions: ["query"],
        type: "web",
        rowLimit: row_limit
      }
    ]
    |> send_request()
    |> query_answer()
  end

  defp post_token(form) do
    config = config()

    [
      method: :post,
      url: @token_url,
      form: [client_id: Keyword.get(config, :client_id), client_secret: Keyword.get(config, :client_secret)] ++ form
    ]
    |> send_request()
    |> token_answer()
  end

  defp send_request(request_options) do
    [retry: false]
    |> Keyword.merge(Keyword.get(config(), :req_options, []))
    |> Req.request(request_options)
  end

  defp config, do: Application.get_env(:dirmoon, __MODULE__, [])

  defp token_answer({:ok, %Req.Response{status: 200, body: %{} = body}}), do: {:ok, body}
  defp token_answer({:ok, %Req.Response{body: %{"error" => "invalid_grant"}}}), do: {:error, :invalid_grant}

  defp token_answer({:ok, %Req.Response{body: %{"error" => error}}}) when is_binary(error),
    do: {:error, "Google OAuth: #{error}"}

  defp token_answer({:ok, %Req.Response{status: status}}), do: {:error, "Google OAuth: HTTP #{status}"}
  defp token_answer({:error, exception}), do: {:error, "Google OAuth: #{Exception.message(exception)}"}

  defp fetch_access_token(%{"access_token" => access_token}) when is_binary(access_token) and access_token != "",
    do: {:ok, access_token}

  defp fetch_access_token(_body), do: {:error, "Google OAuth: no access token"}

  defp ensure_search_console_scope(%{"scope" => scope}) when is_binary(scope) do
    if @search_console_scope in String.split(scope), do: :ok, else: {:error, :search_console_scope_not_granted}
  end

  defp ensure_search_console_scope(_body), do: :ok

  defp fetch_refresh_token(%{"refresh_token" => refresh_token}) when is_binary(refresh_token) and refresh_token != "",
    do: {:ok, refresh_token}

  defp fetch_refresh_token(_body), do: {:error, :no_refresh_token}

  defp id_token_email(%{"id_token" => id_token}) when is_binary(id_token) do
    with [_header, payload | _signature] <- String.split(id_token, "."),
         {:ok, json} <- Base.url_decode64(payload, padding: false),
         {:ok, %{"email" => email}} when is_binary(email) <- Jason.decode(json) do
      {:ok, email}
    else
      _invalid -> {:error, :no_google_email}
    end
  end

  defp id_token_email(_body), do: {:error, :no_google_email}

  defp query_answer({:ok, %Req.Response{status: 200, body: %{} = body}}) do
    {:ok, %{rows: body |> Map.get("rows", []) |> Enum.map(&query_row/1), raw: body}}
  end

  defp query_answer({:ok, %Req.Response{status: 403}}), do: {:error, :forbidden}
  defp query_answer({:ok, %Req.Response{status: 401}}), do: {:error, :unauthorized}

  defp query_answer({:ok, %Req.Response{body: %{"error" => %{"message" => message}}}}) when is_binary(message),
    do: {:error, "Google Search Console: #{message}"}

  defp query_answer({:ok, %Req.Response{status: status}}), do: {:error, "Google Search Console: HTTP #{status}"}
  defp query_answer({:error, exception}), do: {:error, "Google Search Console: #{Exception.message(exception)}"}

  defp query_row(%{"keys" => [query | _other_keys]} = row) do
    %{
      query: query,
      clicks: row["clicks"],
      impressions: row["impressions"],
      ctr: row["ctr"],
      position: row["position"]
    }
  end
end
