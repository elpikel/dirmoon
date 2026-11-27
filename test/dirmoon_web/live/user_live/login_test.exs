defmodule DirmoonWeb.UserLive.LoginTest do
  use DirmoonWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias Dirmoon.Accounts.UserToken
  alias Dirmoon.Repo

  @check_inbox "Check your inbox: if this address has a dirmoon account, a sign-in link is on its way."

  test "the sign-in page asks for an email in English on the auth layout", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/users/log-in")

    assert has_element?(view, "[data-layout=auth]")
    assert has_element?(view, "#login-title", "Sign in")
    assert has_element?(view, "#login-form input[type=email][name='user[email]']")
    assert has_element?(view, "#login-submit[type=submit][data-variant=dark]", "Send sign-in link")
    assert has_element?(view, "#sign-up-link[href='/#sign-up-form-hero']")
  end

  test "the sign-in page asks search engines not to list it and names no canonical address", %{conn: conn} do
    document = conn |> get(~p"/users/log-in") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("meta[name=robots]") |> LazyHTML.attribute("content") == ["noindex"]
    assert document |> LazyHTML.query("link[rel=canonical]") |> Enum.count() == 0
    assert document |> LazyHTML.query("script[type='application/ld+json']") |> Enum.count() == 0
  end

  test "an email that already has a User gets a sign-in link", %{conn: conn} do
    user = insert(:user)
    {:ok, view, _html} = live(conn, ~p"/users/log-in")

    {:ok, redirected_view, _html} =
      view
      |> form("#login-form", user: %{email: user.email})
      |> render_submit()
      |> follow_redirect(conn, ~p"/users/log-in")

    assert has_element?(redirected_view, "#flash-info", @check_inbox)
    assert Repo.get_by!(UserToken, user_id: user.id).context == "login"
    assert_email_sent(to: user.email)
  end

  test "an unknown email gets the same answer and no email", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/users/log-in")

    {:ok, redirected_view, _html} =
      view
      |> form("#login-form", user: %{email: unique_user_email()})
      |> render_submit()
      |> follow_redirect(conn, ~p"/users/log-in")

    assert has_element?(redirected_view, "#flash-info", @check_inbox)
    assert_no_email_sent()
  end

  test "a signed-in user sees the re-authentication note with their email filled in", %{conn: conn} do
    %{conn: conn, user: user} = sign_up_and_log_in_user(%{conn: conn})

    {:ok, view, _html} = live(conn, ~p"/users/log-in")

    assert has_element?(view, "#reauthenticate-notice")
    refute has_element?(view, "#sign-up-link")
    assert has_element?(view, ~s(#login-form input[name="user[email]"][value="#{user.email}"][readonly]))
  end

  test "there is no separate sign-up page under /users", %{conn: conn} do
    conn = get(conn, "/users/register")

    assert html_response(conn, 404)
  end
end
