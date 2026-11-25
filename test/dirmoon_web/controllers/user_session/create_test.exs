defmodule DirmoonWeb.Controllers.UserSession.CreateTest do
  use DirmoonWeb.ConnCase, async: true

  import Dirmoon.AccountsHelpers

  alias Dirmoon.Accounts.User
  alias Dirmoon.Repo

  test "a valid magic link signs a confirmed user in and lands on /app with their menu", %{conn: conn} do
    user = insert(:user)
    %{token: token} = generate_user_magic_link_token(user)

    conn = post(conn, ~p"/users/log-in", %{"user" => %{"token" => token}})

    assert get_session(conn, :user_token)
    assert redirected_to(conn) == ~p"/app"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Welcome back!"

    insert(:market_country)
    insert(:market_language)
    document = conn |> get(~p"/app/research/new") |> html_response(200) |> LazyHTML.from_document()
    assert document |> LazyHTML.query("#user-email") |> LazyHTML.text() == user.email
    assert document |> LazyHTML.query("#settings-link[href='/users/settings']") |> Enum.count() == 1
    assert document |> LazyHTML.query("#log-out-link[href='/users/log-out'][data-method=delete]") |> Enum.count() == 1
  end

  test "a magic link with remember me writes the remember-me cookie", %{conn: conn} do
    %{token: token} = :user |> insert() |> generate_user_magic_link_token()

    conn = post(conn, ~p"/users/log-in", %{"user" => %{"token" => token, "remember_me" => "true"}})

    assert conn.resp_cookies["_dirmoon_web_user_remember_me"]
    assert redirected_to(conn) == ~p"/app"
  end

  test "a magic link returns the user to the page they first asked for", %{conn: conn} do
    %{token: token} = :user |> insert() |> generate_user_magic_link_token()

    conn =
      conn
      |> init_test_session(user_return_to: "/foo/bar")
      |> post(~p"/users/log-in", %{"user" => %{"token" => token}})

    assert redirected_to(conn) == "/foo/bar"
  end

  test "a confirmed magic link confirms a new user and signs them in", %{conn: conn} do
    user = insert(:user, confirmed_at: nil)
    %{token: token} = generate_user_magic_link_token(user)

    conn = post(conn, ~p"/users/log-in", %{"user" => %{"token" => token}, "_action" => "confirmed"})

    assert get_session(conn, :user_token)
    assert redirected_to(conn) == ~p"/app"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Account confirmed. Welcome to dirmoon!"
    assert Repo.get!(User, user.id).confirmed_at
  end

  test "an invalid magic link redirects to sign-in with an error", %{conn: conn} do
    conn = post(conn, ~p"/users/log-in", %{"user" => %{"token" => "invalid"}})

    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "The sign-in link is invalid or has expired."
    assert redirected_to(conn) == ~p"/users/log-in"
    refute get_session(conn, :user_token)
  end

  test "an expired magic link redirects to sign-in without signing in", %{conn: conn} do
    %{token: token, hashed_token: hashed_token} = :user |> insert() |> generate_user_magic_link_token()
    offset_user_token(hashed_token, -16, :minute)

    conn = post(conn, ~p"/users/log-in", %{"user" => %{"token" => token}})

    assert redirected_to(conn) == ~p"/users/log-in"
    refute get_session(conn, :user_token)
  end
end
