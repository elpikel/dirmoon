defmodule DirmoonWeb.Controllers.App.IndexTest do
  use DirmoonWeb.ConnCase, async: true

  alias Dirmoon.Accounts.Membership

  test "a User with no research left lands on the plan screen", %{conn: conn} do
    %{conn: conn} = log_in_user_of(conn, insert(:account, unpaid_access: false))

    conn = get(conn, ~p"/app")

    assert redirected_to(conn) == ~p"/app/billing"
  end

  test "a User with a research left lands on the new research screen", %{conn: conn} do
    account = insert(:account, unpaid_access: false)
    insert(:allowance, account: account, researches: 1)
    %{conn: conn} = log_in_user_of(conn, account)

    conn = get(conn, ~p"/app")

    assert redirected_to(conn) == ~p"/app/research/new"
  end

  test "a User whose Account needs no payment lands on the new research screen", %{conn: conn} do
    %{conn: conn} = log_in_user_of(conn, insert(:account, unpaid_access: true))

    conn = get(conn, ~p"/app")

    assert redirected_to(conn) == ~p"/app/research/new"
  end

  test "a signed-out visitor is sent to sign in", %{conn: conn} do
    conn = get(conn, ~p"/app")

    assert redirected_to(conn) == ~p"/users/log-in"
  end

  defp log_in_user_of(conn, account) do
    user = insert(:user, memberships: [%Membership{account: account}])
    %{conn: log_in_user(conn, user)}
  end
end
