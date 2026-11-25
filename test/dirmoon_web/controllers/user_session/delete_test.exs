defmodule DirmoonWeb.Controllers.UserSession.DeleteTest do
  use DirmoonWeb.ConnCase, async: true

  test "logging out ends the session and returns to the landing page", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})

    conn = delete(conn, ~p"/users/log-out")

    assert redirected_to(conn) == ~p"/"
    refute get_session(conn, :user_token)
    assert conn.assigns.flash == %{}
  end

  test "logging out succeeds for a visitor who is not signed in", %{conn: conn} do
    conn = delete(conn, ~p"/users/log-out")

    assert redirected_to(conn) == ~p"/"
    refute get_session(conn, :user_token)
  end
end
