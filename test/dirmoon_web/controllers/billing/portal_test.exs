defmodule DirmoonWeb.Controllers.Billing.PortalTest do
  use DirmoonWeb.ConnCase, async: true

  import Mox

  alias Dirmoon.Accounts.Membership

  test "managing the plan sends the User to Stripe's customer portal for their Customer", %{conn: conn} do
    %{conn: conn, account: account} = log_in_paying_user(conn, unique_stripe_customer_id())
    stripe_customer_id = account.stripe_customer_id
    return_url = url(~p"/app/billing")

    expect(Dirmoon.StripeMock, :create_portal_session, 1, fn %{
                                                               stripe_customer_id: ^stripe_customer_id,
                                                               return_url: ^return_url
                                                             } ->
      {:ok, %{result: %{url: "https://billing.stripe.com/p/session/test_portal"}, raw: %{}}}
    end)

    conn = post(conn, ~p"/app/billing/portal")

    assert redirected_to(conn) == "https://billing.stripe.com/p/session/test_portal"
  end

  test "an Account that has never paid is told there is nothing to manage yet", %{conn: conn} do
    %{conn: conn} = log_in_paying_user(conn, nil)

    conn = post(conn, ~p"/app/billing/portal")

    assert redirected_to(conn) == ~p"/app/billing"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "You haven't paid for anything yet, so there's no plan to manage."
  end

  test "without Stripe keys on the server the plan screen says payments aren't set up", %{conn: conn} do
    %{conn: conn} = log_in_paying_user(conn, unique_stripe_customer_id())
    expect(Dirmoon.StripeMock, :create_portal_session, 1, fn _request -> {:error, :not_configured} end)

    conn = post(conn, ~p"/app/billing/portal")

    assert redirected_to(conn) == ~p"/app/billing"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Payments aren't set up yet."
  end

  test "when Stripe can't be reached the plan screen says it didn't work", %{conn: conn} do
    %{conn: conn} = log_in_paying_user(conn, unique_stripe_customer_id())

    expect(Dirmoon.StripeMock, :create_portal_session, 1, fn _request ->
      {:error, {:stripe_unreachable, %Req.TransportError{reason: :timeout}}}
    end)

    conn = post(conn, ~p"/app/billing/portal")

    assert redirected_to(conn) == ~p"/app/billing"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "That didn't work. Please try again."
  end

  test "a signed-out visitor is sent to sign in and nothing goes to Stripe", %{conn: conn} do
    conn = post(conn, ~p"/app/billing/portal")

    assert redirected_to(conn) == ~p"/users/log-in"
  end

  defp log_in_paying_user(conn, stripe_customer_id) do
    account = insert(:account, unpaid_access: false, stripe_customer_id: stripe_customer_id)
    user = insert(:user, memberships: [%Membership{account: account}])
    %{conn: log_in_user(conn, user), account: account}
  end
end
