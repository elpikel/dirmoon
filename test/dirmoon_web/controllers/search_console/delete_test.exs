defmodule DirmoonWeb.Controllers.SearchConsole.DeleteTest do
  use DirmoonWeb.ConnCase, async: true

  alias Dirmoon.SearchConsole.Connection

  test "disconnecting removes the account's Search Console connection", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    connection = insert(:search_console_connection, account: scope.account)
    other = insert(:search_console_connection)

    conn = delete(conn, ~p"/app/search-console")

    assert redirected_to(conn) == ~p"/app"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Odłączono Search Console"
    refute Dirmoon.Repo.get(Connection, connection.id)
    assert Dirmoon.Repo.get(Connection, other.id)
  end

  test "a signed-out visitor is sent to sign in and nothing is removed", %{conn: conn} do
    connection = insert(:search_console_connection)

    conn = delete(conn, ~p"/app/search-console")

    assert redirected_to(conn) == ~p"/users/log-in"
    assert Dirmoon.Repo.get(Connection, connection.id)
  end
end
