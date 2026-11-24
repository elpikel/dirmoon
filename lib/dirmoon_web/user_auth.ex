defmodule DirmoonWeb.UserAuth do
  @moduledoc """
  Signs users in and out, loads the current Scope from the session or the
  remember-me cookie, and guards signed-in routes and LiveViews.
  """
  use DirmoonWeb, :verified_routes

  import Phoenix.Controller
  import Plug.Conn

  alias Dirmoon.Accounts
  alias Dirmoon.Accounts.Scope
  alias Dirmoon.Accounts.User

  @max_cookie_age_in_days 14
  @remember_me_cookie "_dirmoon_web_user_remember_me"
  @remember_me_options [
    sign: true,
    max_age: @max_cookie_age_in_days * 24 * 60 * 60,
    same_site: "Lax"
  ]
  @session_reissue_age_in_days 7

  @log_in_required_message "Zaloguj się, aby otworzyć tę stronę."
  @reauthentication_required_message "Zaloguj się ponownie, aby otworzyć tę stronę."

  @doc """
  Logs the user in and redirects to the session's `:user_return_to` path or
  `signed_in_path/1`.
  """
  def log_in_user(conn, user, params \\ %{}) do
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> create_or_extend_session(user, params)
    |> delete_session(:user_return_to)
    |> redirect(to: user_return_to || signed_in_path(conn))
  end

  @doc """
  Logs the user out, clearing the whole session and the remember-me cookie.
  """
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      DirmoonWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session(nil)
    |> delete_resp_cookie(@remember_me_cookie, @remember_me_options)
    |> redirect(to: ~p"/")
  end

  @doc """
  Assigns `:current_scope` from the session token or the remember-me cookie,
  reissuing a session token older than #{@session_reissue_age_in_days} days.
  """
  def fetch_current_scope_for_user(conn, _opts) do
    with {token, conn} <- ensure_user_token(conn),
         {user, token_inserted_at} <- Accounts.get_user_by_session_token(token) do
      conn
      |> assign(:current_scope, Accounts.scope_for_user(user))
      |> maybe_reissue_user_session_token(user, token_inserted_at)
    else
      nil -> assign(conn, :current_scope, nil)
    end
  end

  @doc """
  Disconnects the LiveView sockets of the given session tokens.
  """
  def disconnect_sessions(tokens) do
    Enum.each(tokens, fn %{token: token} ->
      DirmoonWeb.Endpoint.broadcast(user_session_topic(token), "disconnect", %{})
    end)
  end

  @doc """
  Mounts the current Scope in LiveViews.

    * `:mount_current_scope` - assigns `current_scope` from the session, or nil.
    * `:require_authenticated` - as above, and redirects to the sign-in page
      when no user is signed in.
    * `:require_sudo_mode` - redirects to the sign-in page unless the user
      signed in within the last 10 minutes.

      live_session :app, on_mount: [{DirmoonWeb.UserAuth, :require_authenticated}] do
        live "/research/new", NewResearchLive
      end
  """
  def on_mount(:mount_current_scope, _params, session, socket) do
    {:cont, mount_current_scope(socket, session)}
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if signed_in?(socket.assigns.current_scope) do
      {:cont, socket}
    else
      {:halt, redirect_to_log_in(socket, @log_in_required_message)}
    end
  end

  def on_mount(:require_sudo_mode, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if Accounts.sudo_mode?(socket.assigns.current_scope.user, -10) do
      {:cont, socket}
    else
      {:halt, redirect_to_log_in(socket, @reauthentication_required_message)}
    end
  end

  @doc """
  Returns the path to redirect to after signing in: settings when the user
  was already signed in (re-authentication), the app otherwise.
  """
  def signed_in_path(%Plug.Conn{assigns: %{current_scope: %Scope{user: %User{}}}}), do: ~p"/users/settings"
  def signed_in_path(_conn), do: ~p"/app"

  @doc """
  Plug for routes that require a signed-in user. Remembers the requested GET
  path to return to after signing in.
  """
  def require_authenticated_user(conn, _opts) do
    if signed_in?(conn.assigns.current_scope) do
      conn
    else
      conn
      |> put_flash(:error, @log_in_required_message)
      |> maybe_store_return_to()
      |> redirect(to: ~p"/users/log-in")
      |> halt()
    end
  end

  @doc """
  Plug for the signed-out pages (landing, sign-up): sends a signed-in user to
  the app instead.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if signed_in?(conn.assigns.current_scope) do
      conn
      |> redirect(to: ~p"/app")
      |> halt()
    else
      conn
    end
  end

  defp signed_in?(%Scope{user: %User{}}), do: true
  defp signed_in?(_scope), do: false

  defp redirect_to_log_in(socket, message) do
    socket
    |> Phoenix.LiveView.put_flash(:error, message)
    |> Phoenix.LiveView.redirect(to: ~p"/users/log-in")
  end

  defp mount_current_scope(socket, session) do
    Phoenix.Component.assign_new(socket, :current_scope, fn ->
      with user_token when is_binary(user_token) <- session["user_token"],
           {user, _token_inserted_at} <- Accounts.get_user_by_session_token(user_token) do
        Accounts.scope_for_user(user)
      else
        _no_session_user -> nil
      end
    end)
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, conn |> put_token_in_session(token) |> put_session(:user_remember_me, true)}
      end
    end
  end

  defp maybe_reissue_user_session_token(conn, user, token_inserted_at) do
    token_age = DateTime.diff(DateTime.utc_now(:second), token_inserted_at, :day)

    if token_age >= @session_reissue_age_in_days do
      create_or_extend_session(conn, user, %{})
    else
      conn
    end
  end

  defp create_or_extend_session(conn, user, params) do
    token = Accounts.generate_user_session_token(user)
    remember_me = get_session(conn, :user_remember_me)

    conn
    |> renew_session(user)
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params, remember_me)
  end

  defp renew_session(%{assigns: %{current_scope: %Scope{user: %User{id: user_id}}}} = conn, %User{id: user_id}) do
    conn
  end

  defp renew_session(conn, _user) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}, _remember_me),
    do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, token, _params, true), do: write_remember_me_cookie(conn, token)
  defp maybe_write_remember_me_cookie(conn, _token, _params, _remember_me), do: conn

  defp write_remember_me_cookie(conn, token) do
    conn
    |> put_session(:user_remember_me, true)
    |> put_resp_cookie(@remember_me_cookie, token, @remember_me_options)
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, user_session_topic(token))
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  defp user_session_topic(token), do: "users_sessions:#{Base.url_encode64(token)}"
end
