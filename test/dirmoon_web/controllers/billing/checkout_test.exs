defmodule DirmoonWeb.Controllers.Billing.CheckoutTest do
  use DirmoonWeb.ConnCase, async: true

  import Mox

  alias Dirmoon.Accounts.Membership

  test "choosing one research sends the User to Stripe's checkout for the Single Research", %{conn: conn} do
    %{conn: conn, account: account} = log_in_paying_user(conn)
    success_url = url(~p"/app/billing?paid=1")
    cancel_url = url(~p"/app/billing")
    account_id = account.id

    expect(Dirmoon.StripeMock, :create_checkout_session, 1, fn %{
                                                                 product: :single_research,
                                                                 account_id: ^account_id,
                                                                 success_url: ^success_url,
                                                                 cancel_url: ^cancel_url
                                                               } ->
      checkout_session("cs_test_single")
    end)

    conn = post(conn, ~p"/app/billing/checkout", %{"product" => "single_research"})

    assert redirected_to(conn) == "https://checkout.stripe.com/c/pay/cs_test_single"
  end

  test "choosing the monthly plan sends the User to Stripe's checkout for the Subscription", %{conn: conn} do
    %{conn: conn} = log_in_paying_user(conn)

    expect(Dirmoon.StripeMock, :create_checkout_session, 1, fn %{product: :subscription} ->
      checkout_session("cs_test_monthly")
    end)

    conn = post(conn, ~p"/app/billing/checkout", %{"product" => "subscription"})

    assert redirected_to(conn) == "https://checkout.stripe.com/c/pay/cs_test_monthly"
  end

  test "a subscriber choosing the monthly plan again is sent back to the plan screen and nothing goes to Stripe",
       %{conn: conn} do
    %{conn: conn, account: account} = log_in_paying_user(conn)
    insert(:subscription, account: account, status: "active")

    conn = post(conn, ~p"/app/billing/checkout", %{"product" => "subscription"})

    assert redirected_to(conn) == ~p"/app/billing"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "You already have the monthly plan."
  end

  test "without Stripe keys on the server the plan screen says payments aren't set up", %{conn: conn} do
    %{conn: conn} = log_in_paying_user(conn)
    expect(Dirmoon.StripeMock, :create_checkout_session, 1, fn _request -> {:error, :not_configured} end)

    conn = post(conn, ~p"/app/billing/checkout", %{"product" => "single_research"})

    assert redirected_to(conn) == ~p"/app/billing"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Payments aren't set up yet."
  end

  test "when Stripe refuses the checkout the plan screen says it didn't work, without Stripe's details",
       %{conn: conn} do
    %{conn: conn} = log_in_paying_user(conn)

    expect(Dirmoon.StripeMock, :create_checkout_session, 1, fn _request ->
      {:error, {:stripe_refused, %{status: 400, body: %{"error" => %{"message" => "No such price"}}}}}
    end)

    conn = post(conn, ~p"/app/billing/checkout", %{"product" => "subscription"})

    assert redirected_to(conn) == ~p"/app/billing"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "That didn't work. Please try again."
  end

  test "an unknown product is sent back to the plan screen and nothing goes to Stripe", %{conn: conn} do
    %{conn: conn} = log_in_paying_user(conn)

    conn = post(conn, ~p"/app/billing/checkout", %{"product" => "free_month"})

    assert redirected_to(conn) == ~p"/app/billing"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "That didn't work. Please try again."
  end

  test "a checkout without a product is sent back to the plan screen and nothing goes to Stripe", %{conn: conn} do
    %{conn: conn} = log_in_paying_user(conn)

    conn = post(conn, ~p"/app/billing/checkout", %{})

    assert redirected_to(conn) == ~p"/app/billing"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "That didn't work. Please try again."
  end

  test "a signed-out visitor is sent to sign in and nothing goes to Stripe", %{conn: conn} do
    conn = post(conn, ~p"/app/billing/checkout", %{"product" => "single_research"})

    assert redirected_to(conn) == ~p"/users/log-in"
  end

  defp log_in_paying_user(conn) do
    account = insert(:account, unpaid_access: false, stripe_customer_id: unique_stripe_customer_id())
    user = insert(:user, memberships: [%Membership{account: account}])
    %{conn: log_in_user(conn, user), account: account}
  end

  defp checkout_session(id),
    do: {:ok, %{result: %{id: id, url: "https://checkout.stripe.com/c/pay/" <> id}, raw: %{"id" => id}}}
end
