defmodule DirmoonWeb.SearchConsoleController do
  use DirmoonWeb, :controller

  alias Dirmoon.SearchConsole

  @state_session_key :search_console_oauth_state
  @return_to_session_key :search_console_return_to
  @state_bytes 32
  @default_return_to "/app"
  @failed_message "Nie udało się połączyć z Search Console"
  @not_configured_message "Search Console nie jest skonfigurowane"

  def connect(conn, params) do
    state = @state_bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    return_to = local_app_path(params["return_to"])

    case SearchConsole.authorize_url(state, callback_url()) do
      {:ok, authorize_url} ->
        conn
        |> put_session(@state_session_key, state)
        |> put_session(@return_to_session_key, return_to)
        |> redirect(external: authorize_url)

      {:error, :search_console_not_configured} ->
        conn
        |> put_flash(:error, @not_configured_message)
        |> redirect(to: return_to)

      {:error, _reason} ->
        conn
        |> put_flash(:error, @failed_message)
        |> redirect(to: return_to)
    end
  end

  def callback(conn, params) do
    issued_state = get_session(conn, @state_session_key)
    return_to = get_session(conn, @return_to_session_key) || @default_return_to

    conn =
      conn
      |> delete_session(@state_session_key)
      |> delete_session(@return_to_session_key)

    with true <- issued_state?(issued_state, params["state"]),
         {:ok, code} <- granted_code(params),
         {:ok, connection} <-
           SearchConsole.connect(conn.assigns.current_scope, %{code: code, redirect_uri: callback_url()}) do
      conn
      |> put_flash(:info, "Połączono z Search Console (#{connection.google_email})")
      |> redirect(to: return_to)
    else
      _failed ->
        conn
        |> put_flash(:error, @failed_message)
        |> redirect(to: @default_return_to)
    end
  end

  def delete(conn, _params) do
    :ok = SearchConsole.disconnect(conn.assigns.current_scope)

    conn
    |> put_flash(:info, "Odłączono Search Console")
    |> redirect(to: @default_return_to)
  end

  defp callback_url, do: url(~p"/app/search-console/callback")

  defp issued_state?(issued_state, state) when is_binary(issued_state) and is_binary(state),
    do: Plug.Crypto.secure_compare(issued_state, state)

  defp issued_state?(_issued_state, _state), do: false

  defp granted_code(%{"error" => _error}), do: :error
  defp granted_code(%{"code" => code}) when is_binary(code) and code != "", do: {:ok, code}
  defp granted_code(_params), do: :error

  defp local_app_path("/app" <> rest = path) do
    if app_path_rest?(rest) and plain_text?(path) and not String.contains?(path, ["//", "\\"]),
      do: path,
      else: @default_return_to
  end

  defp local_app_path(_path), do: @default_return_to

  defp app_path_rest?(""), do: true
  defp app_path_rest?(<<separator, _rest::binary>>) when separator in [?/, ??, ?#], do: true
  defp app_path_rest?(_rest), do: false

  defp plain_text?(path), do: String.printable?(path) and not String.match?(path, ~r/[[:cntrl:]]/u)
end
