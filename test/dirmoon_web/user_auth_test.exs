defmodule DirmoonWeb.UserAuthTest do
  use DirmoonWeb.ConnCase, async: true

  import Dirmoon.AccountsHelpers
  import Phoenix.LiveViewTest

  alias Dirmoon.Accounts
  alias Dirmoon.Accounts.Account
  alias Dirmoon.Accounts.Scope
  alias DirmoonWeb.UserAuth
  alias Phoenix.LiveView
  alias Phoenix.Socket.Broadcast

  @remember_me_cookie "_dirmoon_web_user_remember_me"
  @remember_me_cookie_max_age 60 * 60 * 24 * 14

  test "a signed-out visitor opening /app is redirected to the sign-in page", %{conn: conn} do
    assert {:error, {:redirect, %{to: path, flash: flash}}} = live(conn, ~p"/app")

    assert path == ~p"/users/log-in"
    assert %{"error" => "Sign in to open this page."} = flash
  end

  test "a signed-out visitor's request for /app is redirected to sign-in and remembered", %{conn: conn} do
    conn = get(conn, ~p"/app?tab=runs")

    assert redirected_to(conn) == ~p"/users/log-in"
    assert get_session(conn, :user_return_to) == "/app?tab=runs"
  end

  test "an /app LiveView mounts with the user and the Account of their first Membership", %{conn: conn} do
    %{conn: conn, user: user} = sign_up_and_log_in_user(%{conn: conn})
    first_account = Accounts.account_for_user(user)
    later_account = insert(:account)

    insert(:membership,
      user: user,
      account: later_account,
      inserted_at: DateTime.shift(DateTime.utc_now(:second), hour: 1)
    )

    insert(:market_country)
    insert(:market_language)
    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    assert %Scope{user: scope_user, account: %Account{id: account_id}} = current_scope(view)
    assert scope_user.id == user.id
    assert account_id == first_account.id
    assert has_element?(view, "#user-email", user.email)
  end

  test "log_in_user stores the session token and redirects to /app", %{conn: conn} do
    user = signed_in_user()

    conn = conn |> session_conn() |> UserAuth.log_in_user(user)

    assert token = get_session(conn, :user_token)
    assert get_session(conn, :live_socket_id) == "users_sessions:#{Base.url_encode64(token)}"
    assert redirected_to(conn) == ~p"/app"
    assert Accounts.get_user_by_session_token(token)
  end

  test "log_in_user clears everything previously stored in the session", %{conn: conn} do
    user = signed_in_user()

    conn = conn |> session_conn() |> put_session(:to_be_removed, "value") |> UserAuth.log_in_user(user)

    refute get_session(conn, :to_be_removed)
  end

  test "log_in_user keeps the session when the same user re-authenticates", %{conn: conn} do
    user = signed_in_user()

    conn =
      conn
      |> session_conn()
      |> assign(:current_scope, Accounts.scope_for_user(user))
      |> put_session(:to_be_removed, "value")
      |> UserAuth.log_in_user(user)

    assert get_session(conn, :to_be_removed)
  end

  test "log_in_user clears the session when another user signs in", %{conn: conn} do
    user = signed_in_user()

    conn =
      conn
      |> session_conn()
      |> assign(:current_scope, Accounts.scope_for_user(insert(:user)))
      |> put_session(:to_be_removed, "value")
      |> UserAuth.log_in_user(user)

    refute get_session(conn, :to_be_removed)
  end

  test "log_in_user redirects to the stored return path and forgets it", %{conn: conn} do
    user = signed_in_user()

    conn =
      conn
      |> session_conn()
      |> assign(:current_scope, Accounts.scope_for_user(user))
      |> put_session(:user_return_to, "/hello")
      |> UserAuth.log_in_user(user)

    assert redirected_to(conn) == "/hello"
    refute get_session(conn, :user_return_to)
  end

  test "log_in_user redirects an already signed-in user to settings", %{conn: conn} do
    user = signed_in_user()

    conn =
      conn
      |> session_conn()
      |> assign(:current_scope, Accounts.scope_for_user(user))
      |> UserAuth.log_in_user(user)

    assert redirected_to(conn) == ~p"/users/settings"
  end

  test "log_in_user writes a remember-me cookie when asked", %{conn: conn} do
    user = signed_in_user()

    conn = conn |> session_conn() |> fetch_cookies() |> UserAuth.log_in_user(user, %{"remember_me" => "true"})

    assert get_session(conn, :user_token) == conn.cookies[@remember_me_cookie]
    assert get_session(conn, :user_remember_me) == true
    assert %{value: signed_token, max_age: @remember_me_cookie_max_age} = conn.resp_cookies[@remember_me_cookie]
    assert signed_token != get_session(conn, :user_token)
  end

  test "log_in_user writes the remember-me cookie again when the previous session had it", %{conn: conn} do
    user = signed_in_user()

    conn =
      conn
      |> Map.replace!(:secret_key_base, DirmoonWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{user_remember_me: true})
      |> fetch_cookies()
      |> UserAuth.log_in_user(user, %{})

    assert %{value: signed_token, max_age: @remember_me_cookie_max_age} = conn.resp_cookies[@remember_me_cookie]
    assert signed_token != get_session(conn, :user_token)
    assert get_session(conn, :user_remember_me) == true
  end

  test "log_out_user erases the session, the cookie and the session token", %{conn: conn} do
    user_token = Accounts.generate_user_session_token(insert(:user))

    conn =
      conn
      |> session_conn()
      |> put_session(:user_token, user_token)
      |> put_req_cookie(@remember_me_cookie, user_token)
      |> fetch_cookies()
      |> UserAuth.log_out_user()

    refute get_session(conn, :user_token)
    refute conn.cookies[@remember_me_cookie]
    assert %{max_age: 0} = conn.resp_cookies[@remember_me_cookie]
    assert redirected_to(conn) == ~p"/"
    refute Accounts.get_user_by_session_token(user_token)
  end

  test "log_out_user disconnects the session's LiveViews", %{conn: conn} do
    live_socket_id = "users_sessions:abcdef-token"
    DirmoonWeb.Endpoint.subscribe(live_socket_id)

    conn
    |> session_conn()
    |> put_session(:live_socket_id, live_socket_id)
    |> UserAuth.log_out_user()

    assert_receive %Broadcast{event: "disconnect", topic: ^live_socket_id}
  end

  test "log_out_user works for a visitor who is not signed in", %{conn: conn} do
    conn = conn |> session_conn() |> fetch_cookies() |> UserAuth.log_out_user()

    refute get_session(conn, :user_token)
    assert %{max_age: 0} = conn.resp_cookies[@remember_me_cookie]
    assert redirected_to(conn) == ~p"/"
  end

  test "fetch_current_scope_for_user builds the scope from the session token", %{conn: conn} do
    user = signed_in_user()
    user_token = Accounts.generate_user_session_token(user)

    conn = conn |> session_conn() |> put_session(:user_token, user_token) |> UserAuth.fetch_current_scope_for_user([])

    assert conn.assigns.current_scope.user.id == user.id
    assert conn.assigns.current_scope.user.authenticated_at == user.authenticated_at
    assert conn.assigns.current_scope.account.id == Accounts.account_for_user(user).id
    assert get_session(conn, :user_token) == user_token
  end

  test "fetch_current_scope_for_user builds the scope from the remember-me cookie", %{conn: conn} do
    user = signed_in_user()

    logged_in_conn =
      conn |> session_conn() |> fetch_cookies() |> UserAuth.log_in_user(user, %{"remember_me" => "true"})

    user_token = logged_in_conn.cookies[@remember_me_cookie]
    %{value: signed_token} = logged_in_conn.resp_cookies[@remember_me_cookie]

    conn =
      conn
      |> session_conn()
      |> put_req_cookie(@remember_me_cookie, signed_token)
      |> UserAuth.fetch_current_scope_for_user([])

    assert conn.assigns.current_scope.user.id == user.id
    assert get_session(conn, :user_token) == user_token
    assert get_session(conn, :user_remember_me)
    assert get_session(conn, :live_socket_id) == "users_sessions:#{Base.url_encode64(user_token)}"
  end

  test "fetch_current_scope_for_user assigns no scope without a session token", %{conn: conn} do
    _token = Accounts.generate_user_session_token(insert(:user))

    conn = conn |> session_conn() |> UserAuth.fetch_current_scope_for_user([])

    refute get_session(conn, :user_token)
    refute conn.assigns.current_scope
  end

  test "fetch_current_scope_for_user reissues an old token and refreshes the cookie", %{conn: conn} do
    user = signed_in_user()

    logged_in_conn =
      conn |> session_conn() |> fetch_cookies() |> UserAuth.log_in_user(user, %{"remember_me" => "true"})

    token = logged_in_conn.cookies[@remember_me_cookie]
    %{value: signed_token} = logged_in_conn.resp_cookies[@remember_me_cookie]
    offset_user_token(token, -10, :day)

    conn =
      conn
      |> session_conn()
      |> put_session(:user_token, token)
      |> put_session(:user_remember_me, true)
      |> put_req_cookie(@remember_me_cookie, signed_token)
      |> UserAuth.fetch_current_scope_for_user([])

    assert conn.assigns.current_scope.user.id == user.id
    assert new_token = get_session(conn, :user_token)
    assert new_token != token
    assert %{value: new_signed_token, max_age: @remember_me_cookie_max_age} = conn.resp_cookies[@remember_me_cookie]
    assert new_signed_token != signed_token
  end

  test "fetch_current_scope_for_user fails fast for a user with no Membership", %{conn: conn} do
    user_token = Accounts.generate_user_session_token(insert(:user, memberships: []))

    assert_raise FunctionClauseError, fn ->
      conn |> session_conn() |> put_session(:user_token, user_token) |> UserAuth.fetch_current_scope_for_user([])
    end
  end

  test "on_mount :mount_current_scope assigns the scope of a valid session token", %{conn: conn} do
    user = insert(:user)

    session =
      conn |> session_conn() |> put_session(:user_token, Accounts.generate_user_session_token(user)) |> get_session()

    {:cont, socket} = UserAuth.on_mount(:mount_current_scope, %{}, session, %LiveView.Socket{})

    assert socket.assigns.current_scope.user.id == user.id
    assert socket.assigns.current_scope.account.id == Accounts.account_for_user(user).id
  end

  test "on_mount :mount_current_scope assigns no scope for an invalid session token", %{conn: conn} do
    session = conn |> session_conn() |> put_session(:user_token, "invalid_token") |> get_session()

    {:cont, socket} = UserAuth.on_mount(:mount_current_scope, %{}, session, %LiveView.Socket{})

    assert socket.assigns.current_scope == nil
  end

  test "on_mount :mount_current_scope assigns no scope without a session token", %{conn: conn} do
    session = conn |> session_conn() |> get_session()

    {:cont, socket} = UserAuth.on_mount(:mount_current_scope, %{}, session, %LiveView.Socket{})

    assert socket.assigns.current_scope == nil
  end

  test "on_mount :require_authenticated continues with the scope of a valid session token", %{conn: conn} do
    user = insert(:user)

    session =
      conn |> session_conn() |> put_session(:user_token, Accounts.generate_user_session_token(user)) |> get_session()

    {:cont, socket} = UserAuth.on_mount(:require_authenticated, %{}, session, %LiveView.Socket{})

    assert socket.assigns.current_scope.user.id == user.id
  end

  test "on_mount :require_authenticated halts for an invalid session token", %{conn: conn} do
    session = conn |> session_conn() |> put_session(:user_token, "invalid_token") |> get_session()

    {:halt, socket} = UserAuth.on_mount(:require_authenticated, %{}, session, live_socket())

    assert socket.assigns.current_scope == nil
  end

  test "on_mount :require_authenticated halts without a session token", %{conn: conn} do
    session = conn |> session_conn() |> get_session()

    {:halt, socket} = UserAuth.on_mount(:require_authenticated, %{}, session, live_socket())

    assert socket.assigns.current_scope == nil
  end

  test "on_mount :require_sudo_mode continues for a sign-in in the last 10 minutes", %{conn: conn} do
    user = signed_in_user()

    session =
      conn |> session_conn() |> put_session(:user_token, Accounts.generate_user_session_token(user)) |> get_session()

    assert {:cont, _socket} = UserAuth.on_mount(:require_sudo_mode, %{}, session, live_socket())
  end

  test "on_mount :require_sudo_mode halts for an older sign-in", %{conn: conn} do
    eleven_minutes_ago = :second |> DateTime.utc_now() |> DateTime.shift(minute: -11)
    user = %{insert(:user) | authenticated_at: eleven_minutes_ago}

    session =
      conn |> session_conn() |> put_session(:user_token, Accounts.generate_user_session_token(user)) |> get_session()

    assert {:halt, _socket} = UserAuth.on_mount(:require_sudo_mode, %{}, session, live_socket())
  end

  test "require_authenticated_user redirects a signed-out visitor to sign-in", %{conn: conn} do
    conn =
      conn
      |> session_conn()
      |> UserAuth.fetch_current_scope_for_user([])
      |> fetch_flash()
      |> UserAuth.require_authenticated_user([])

    assert conn.halted
    assert redirected_to(conn) == ~p"/users/log-in"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Sign in to open this page."
  end

  test "require_authenticated_user remembers the GET path to return to", %{conn: conn} do
    conn = conn |> session_conn() |> UserAuth.fetch_current_scope_for_user([]) |> fetch_flash()

    halted_conn = UserAuth.require_authenticated_user(%{conn | path_info: ["foo"], query_string: "bar=baz"}, [])

    assert halted_conn.halted
    assert get_session(halted_conn, :user_return_to) == "/foo?bar=baz"
  end

  test "require_authenticated_user does not remember a non-GET path", %{conn: conn} do
    conn = conn |> session_conn() |> UserAuth.fetch_current_scope_for_user([]) |> fetch_flash()

    halted_conn =
      UserAuth.require_authenticated_user(%{conn | path_info: ["foo"], query_string: "bar", method: "POST"}, [])

    assert halted_conn.halted
    refute get_session(halted_conn, :user_return_to)
  end

  test "require_authenticated_user lets a signed-in user through", %{conn: conn} do
    conn =
      conn
      |> session_conn()
      |> assign(:current_scope, Accounts.scope_for_user(insert(:user)))
      |> UserAuth.require_authenticated_user([])

    refute conn.halted
    refute conn.status
  end

  test "disconnect_sessions broadcasts a disconnect for each token" do
    DirmoonWeb.Endpoint.subscribe("users_sessions:#{Base.url_encode64("token1")}")
    DirmoonWeb.Endpoint.subscribe("users_sessions:#{Base.url_encode64("token2")}")

    UserAuth.disconnect_sessions([%{token: "token1"}, %{token: "token2"}])

    assert_receive %Broadcast{event: "disconnect", topic: "users_sessions:dG9rZW4x"}
    assert_receive %Broadcast{event: "disconnect", topic: "users_sessions:dG9rZW4y"}
  end

  defp signed_in_user do
    %{insert(:user) | authenticated_at: DateTime.utc_now(:second)}
  end

  defp session_conn(conn) do
    conn
    |> Map.replace!(:secret_key_base, DirmoonWeb.Endpoint.config(:secret_key_base))
    |> init_test_session(%{})
  end

  defp live_socket do
    %LiveView.Socket{endpoint: DirmoonWeb.Endpoint, assigns: %{__changed__: %{}, flash: %{}}}
  end

  defp current_scope(view) do
    :sys.get_state(view.pid).socket.assigns.current_scope
  end
end
