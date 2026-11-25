defmodule DirmoonWeb.UserLive.ConfirmationTest do
  use DirmoonWeb.ConnCase, async: true

  import Dirmoon.AccountsHelpers
  import Phoenix.LiveViewTest

  alias Dirmoon.Accounts
  alias Dirmoon.Accounts.User
  alias Dirmoon.Repo

  test "opening a sign-in link and confirming signs the user in and lands on /app", %{conn: conn} do
    user = insert(:user, confirmed_at: nil)
    token = extract_user_token(fn url -> Accounts.deliver_login_instructions(user, url) end)

    {:ok, view, _html} = live(conn, ~p"/users/log-in/#{token}")
    form = form(view, "#confirmation-form", %{"user" => %{"token" => token}})
    render_submit(form)
    conn = follow_trigger_action(form, conn)

    assert get_session(conn, :user_token)
    assert redirected_to(conn) == ~p"/app"
    assert Repo.get!(User, user.id).confirmed_at

    insert(:market_country)
    insert(:market_language)
    {:ok, app_view, _html} = conn |> recycle() |> live(~p"/app/research/new")
    assert has_element?(app_view, "#research-form")
    assert has_element?(app_view, "#user-email", user.email)
  end

  test "a new user's link shows the confirm screen in English", %{conn: conn} do
    user = insert(:user, confirmed_at: nil)
    token = extract_user_token(fn url -> Accounts.deliver_login_instructions(user, url) end)

    {:ok, view, _html} = live(conn, ~p"/users/log-in/#{token}")

    assert has_element?(view, "[data-layout=auth]")
    assert has_element?(view, "#confirmation-title", "Confirm your account")
    assert has_element?(view, "#confirmation-form[action='/users/log-in?_action=confirmed']")
    assert has_element?(view, "#confirmation-form input[type=checkbox][name='user[remember_me]'][checked]")
    assert has_element?(view, "#confirmation-submit[data-variant=dark]", "Confirm and sign in")
  end

  test "a confirmed user's link shows the sign-in screen", %{conn: conn} do
    user = insert(:user)
    token = extract_user_token(fn url -> Accounts.deliver_login_instructions(user, url) end)

    {:ok, view, _html} = live(conn, ~p"/users/log-in/#{token}")

    assert has_element?(view, "#confirmation-title", "Sign in")
    assert has_element?(view, "#confirmation-form[action='/users/log-in']")
    assert has_element?(view, "#confirmation-form input[name='user[remember_me]']")
  end

  test "a signed-in user's link offers sign-in without remember me", %{conn: conn} do
    user = insert(:user)
    conn = log_in_user(conn, user)
    token = extract_user_token(fn url -> Accounts.deliver_login_instructions(user, url) end)

    {:ok, view, _html} = live(conn, ~p"/users/log-in/#{token}")

    assert has_element?(view, "#confirmation-submit", "Sign in")
    refute has_element?(view, "#confirmation-form input[name='user[remember_me]']")
  end

  test "a confirmed user signs in without changing confirmed_at, and the link works once", %{conn: conn} do
    user = insert(:user)
    token = extract_user_token(fn url -> Accounts.deliver_login_instructions(user, url) end)

    {:ok, view, _html} = live(conn, ~p"/users/log-in/#{token}")
    form = form(view, "#confirmation-form", %{"user" => %{"token" => token}})
    render_submit(form)
    conn = follow_trigger_action(form, conn)

    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Welcome back!"
    assert Repo.get!(User, user.id).confirmed_at == user.confirmed_at

    assert {:error, {:live_redirect, %{to: path, flash: flash}}} = live(build_conn(), ~p"/users/log-in/#{token}")
    assert path == ~p"/users/log-in"
    assert %{"error" => "The sign-in link is invalid or has expired."} = flash
  end

  test "an invalid link redirects to sign-in with an error", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: path, flash: flash}}} = live(conn, ~p"/users/log-in/invalid-token")

    assert path == ~p"/users/log-in"
    assert %{"error" => "The sign-in link is invalid or has expired."} = flash
  end
end
