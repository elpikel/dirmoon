defmodule DirmoonWeb.BillingLiveTest do
  use DirmoonWeb.ConnCase, async: true

  import Dirmoon.StripeEventFixtures
  import Phoenix.LiveViewTest

  alias Dirmoon.Accounts.Membership
  alias Dirmoon.Accounts.Scope
  alias Dirmoon.Billing

  test "the plan screen is the app's Plan screen", %{conn: conn} do
    %{conn: conn} = log_in_paying_user(conn)

    {:ok, view, _html} = live(conn, ~p"/app/billing")

    assert has_element?(view, "#app-context", "/ plan")
    assert has_element?(view, "#app-nav #nav-billing[aria-current=page]", "Plan")
    assert has_element?(view, "#app-main #billing-screen")
  end

  test "the status row says how many researches are left", %{conn: conn} do
    %{conn: conn, account: account} = log_in_paying_user(conn)
    insert(:allowance, account: account, source: :subscription_month, researches: 3, valid_until: days_from_now(20))

    {:ok, view, _html} = live(conn, ~p"/app/billing")

    assert has_element?(view, "#app-status #billing-status-line", "You have 3 researches left.")
  end

  test "with one research left the status row says so in the singular", %{conn: conn} do
    %{conn: conn, account: account} = log_in_paying_user(conn)
    insert(:allowance, account: account, researches: 1)

    {:ok, view, _html} = live(conn, ~p"/app/billing")

    assert has_element?(view, "#billing-status-line", "You have 1 research left.")
  end

  test "with no research left the status row asks how the User wants to pay", %{conn: conn} do
    %{conn: conn} = log_in_paying_user(conn)

    {:ok, view, _html} = live(conn, ~p"/app/billing")

    assert has_element?(view, "#billing-status-line", "You have no research left. Pick how you want to pay.")
  end

  test "an Account that needs no payment is told so, and can still pay", %{conn: conn} do
    %{conn: conn} = log_in_user_of(conn, insert(:account, unpaid_access: true))

    {:ok, view, _html} = live(conn, ~p"/app/billing")

    assert has_element?(view, "#billing-status-line", "Your account doesn't need a plan.")
    assert has_element?(view, "#single-research-checkout")
    assert has_element?(view, "#monthly-plan-checkout")
  end

  test "the two ways to pay show the configured prices and what a research includes", %{conn: conn} do
    %{conn: conn} = log_in_paying_user(conn)
    offer = Billing.offer()

    {:ok, view, _html} = live(conn, ~p"/app/billing")

    assert has_element?(view, "#single-research-option", "One research")
    assert has_element?(view, "#single-research-price", "$#{offer.single_price}")
    assert has_element?(view, "#single-research-option", "paid once")
    assert has_element?(view, "#monthly-plan-option", "Monthly plan")
    assert has_element?(view, "#monthly-plan-price", "$#{offer.monthly_price}")
    assert has_element?(view, "#monthly-plan-option", "a month")
    assert has_element?(view, "#monthly-plan-option", "#{offer.monthly_researches} researches a month")

    for option <- ~w(single-research monthly-plan) do
      assert has_element?(view, "##{option}-includes li", "Up to #{offer.briefs_per_research} briefs")

      assert has_element?(
               view,
               "##{option}-includes li",
               "Up to #{offer.price_checks_per_research} competitor price checks"
             )

      assert has_element?(view, "##{option}-includes li", "For an existing site, a scan of your site")
    end
  end

  test "each way to pay is a form posting its product to checkout with the CSRF token", %{conn: conn} do
    %{conn: conn} = log_in_paying_user(conn)

    {:ok, view, _html} = live(conn, ~p"/app/billing")

    for {form, product} <- [{"#single-research-checkout", "single_research"}, {"#monthly-plan-checkout", "subscription"}] do
      assert has_element?(view, "form#{form}[method=post][action='/app/billing/checkout']")
      assert has_element?(view, "#{form} input[type=hidden][name=product][value=#{product}]")
      assert has_element?(view, "#{form} input[type=hidden][name=_csrf_token]")
      assert has_element?(view, "#{form} button[type=submit]")
    end
  end

  test "without a running plan the monthly plan is the one primary action", %{conn: conn} do
    %{conn: conn} = log_in_paying_user(conn)

    {:ok, view, _html} = live(conn, ~p"/app/billing")

    assert has_element?(view, "#monthly-plan-checkout button[data-variant=lime]", "Start the monthly plan")
    assert has_element?(view, "#single-research-checkout button[data-variant=outline]", "Buy one research")

    assert view |> render() |> LazyHTML.from_document() |> LazyHTML.query("#app-main [data-variant=lime]") |> Enum.count() ==
             1
  end

  test "the two ways to pay stack on a narrow screen and sit side by side on a wide one", %{conn: conn} do
    %{conn: conn} = log_in_paying_user(conn)

    {:ok, view, _html} = live(conn, ~p"/app/billing")

    assert has_element?(view, ~s(#billing-options[class~="grid"][class~="min-[720px]:grid-cols-2"]))
    refute has_element?(view, ~s(#billing-options[class~="grid-cols-2"]))
  end

  test "an Account that never subscribed is told it has no monthly plan and has no plan to manage", %{conn: conn} do
    %{conn: conn} = log_in_paying_user(conn)

    {:ok, view, _html} = live(conn, ~p"/app/billing")

    assert has_element?(view, "#plan-state", "You don't have a monthly plan.")
    refute has_element?(view, "#manage-plan")
  end

  test "a running plan shows the date it renews, offers Manage plan and a Single Research, and no second plan",
       %{conn: conn} do
    %{conn: conn, account: account} = log_in_paying_user(conn)
    period_end = days_from_now(12)
    insert(:subscription, account: account, status: "active", current_period_end: period_end)

    {:ok, view, _html} = live(conn, ~p"/app/billing")

    assert has_element?(view, "#plan-state", "Your monthly plan renews on #{plain_date(period_end)}.")
    assert has_element?(view, "form#manage-plan[method=post][action='/app/billing/portal']")
    assert has_element?(view, "#manage-plan input[type=hidden][name=_csrf_token]")
    assert has_element?(view, "#manage-plan button[type=submit]", "Manage plan")
    assert has_element?(view, "#single-research-checkout")
    refute has_element?(view, "#monthly-plan-checkout")
    assert has_element?(view, "#monthly-plan-current", "This is your plan.")
  end

  test "a running plan whose month Stripe hasn't reported is simply active", %{conn: conn} do
    %{conn: conn, account: account} = log_in_paying_user(conn)
    insert(:subscription, account: account, status: "active", current_period_end: nil)

    {:ok, view, _html} = live(conn, ~p"/app/billing")

    assert has_element?(view, "#plan-state", "Your monthly plan is active.")
  end

  test "a plan cancelled for the end of its month shows the day it ends", %{conn: conn} do
    %{conn: conn, account: account} = log_in_paying_user(conn)
    ends_at = days_from_now(9)
    insert(:subscription, account: account, status: "active", ends_at: ends_at)

    {:ok, view, _html} = live(conn, ~p"/app/billing")

    assert has_element?(view, "#plan-state", "Your monthly plan ends on #{plain_date(ends_at)}.")
    assert has_element?(view, "#manage-plan")
    refute has_element?(view, "#monthly-plan-checkout")
  end

  test "a plan whose payment failed says so and offers Manage plan to fix the card", %{conn: conn} do
    for status <- ~w(past_due unpaid) do
      %{conn: conn, account: account} = log_in_paying_user(conn)
      insert(:subscription, account: account, status: status)

      {:ok, view, _html} = live(conn, ~p"/app/billing")

      assert has_element?(
               view,
               "#plan-state[data-problem]",
               "The last payment for your monthly plan didn't go through. Update your card in Manage plan."
             )

      assert has_element?(view, "#plan-state .text-warn")
      assert has_element?(view, "#manage-plan")
    end
  end

  test "a plan that has ended says so and offers the monthly plan again", %{conn: conn} do
    %{conn: conn, account: account} = log_in_paying_user(conn)
    insert(:subscription, account: account, status: "canceled")

    {:ok, view, _html} = live(conn, ~p"/app/billing")

    assert has_element?(view, "#plan-state", "Your monthly plan has ended.")
    assert has_element?(view, "#monthly-plan-checkout button[data-variant=lime]")
    assert has_element?(view, "#manage-plan")
  end

  test "a plan in any other state asks the User to look in Manage plan", %{conn: conn} do
    for status <- ~w(incomplete paused) do
      %{conn: conn, account: account} = log_in_paying_user(conn)
      insert(:subscription, account: account, status: status)

      {:ok, view, _html} = live(conn, ~p"/app/billing")

      assert has_element?(
               view,
               "#plan-state[data-problem]",
               "Your monthly plan needs your attention. Open Manage plan to see why."
             )

      assert has_element?(view, "#plan-state .text-warn")
      refute has_element?(view, "#monthly-plan-checkout")
    end
  end

  test "coming back from a payment that isn't counted yet says it is being confirmed", %{conn: conn} do
    %{conn: conn} = log_in_paying_user(conn)

    {:ok, view, _html} = live(conn, ~p"/app/billing?paid=1")

    assert has_element?(view, "#payment-confirming[role=status]", "I'm confirming your payment…")
    refute has_element?(view, "#payment-received")
  end

  test "while a payment is being confirmed the status row doesn't ask the User to pay", %{conn: conn} do
    %{conn: conn} = log_in_paying_user(conn)

    {:ok, view, _html} = live(conn, ~p"/app/billing?paid=1")

    assert has_element?(view, "#billing-status-line", "You have no research left.")
    refute has_element?(view, "#billing-status-line", "Pick how you want to pay")
  end

  test "a subscriber whose month is used up is told they can buy one more research", %{conn: conn} do
    %{conn: conn, account: account} = log_in_paying_user(conn)
    insert(:subscription, account: account, status: "active")

    {:ok, view, _html} = live(conn, ~p"/app/billing")

    assert has_element?(
             view,
             "#billing-status-line",
             "You have no research left this month. You can buy one more."
           )

    refute has_element?(view, "#billing-status-line", "Pick how you want to pay")
  end

  test "after a plan has ended the status row asks how the User wants to pay", %{conn: conn} do
    %{conn: conn, account: account} = log_in_paying_user(conn)
    insert(:subscription, account: account, status: "canceled")

    {:ok, view, _html} = live(conn, ~p"/app/billing")

    assert has_element?(view, "#billing-status-line", "You have no research left. Pick how you want to pay.")
  end

  test "the research shows as soon as Stripe's event adds it", %{conn: conn} do
    %{conn: conn, account: account} = log_in_paying_user(conn)
    {:ok, view, _html} = live(conn, ~p"/app/billing?paid=1")

    assert Billing.handle_event(event("checkout.session.completed", checkout_session(account, %{}))) == :ok

    assert has_element?(view, "#payment-received[role=status]", "Payment received.")
    assert has_element?(view, "#billing-status-line", "You have 1 research left.")
    refute has_element?(view, "#payment-confirming")
  end

  test "a plan update without a paid month keeps saying the payment is being confirmed", %{conn: conn} do
    %{conn: conn, account: account} = log_in_paying_user(conn)
    {:ok, view, _html} = live(conn, ~p"/app/billing?paid=1")

    assert Billing.handle_event(event("customer.subscription.created", subscription_object(account))) == :ok

    assert has_element?(view, "#payment-confirming", "I'm confirming your payment…")
    assert has_element?(view, "#plan-state", "Your monthly plan is active.")
  end

  test "coming back with researches already left doesn't claim the payment arrived", %{conn: conn} do
    %{conn: conn, account: account} = log_in_paying_user(conn)
    insert(:allowance, account: account, researches: 1)

    {:ok, view, _html} = live(conn, ~p"/app/billing?paid=1")

    assert has_element?(
             view,
             "#payment-may-be-counted[role=status]",
             "If your payment isn't counted below yet, it will be as soon as Stripe confirms it."
           )

    refute has_element?(view, "#payment-confirming")
    refute has_element?(view, "#payment-received")
  end

  test "with researches already left the payment shows as received once Stripe's event adds it", %{conn: conn} do
    %{conn: conn, account: account} = log_in_paying_user(conn)
    insert(:allowance, account: account, researches: 1)
    {:ok, view, _html} = live(conn, ~p"/app/billing?paid=1")

    assert Billing.handle_event(event("checkout.session.completed", checkout_session(account, %{}))) == :ok

    assert has_element?(view, "#payment-received", "Payment received.")
    assert has_element?(view, "#billing-status-line", "You have 2 researches left.")
    refute has_element?(view, "#payment-may-be-counted")
  end

  test "an update outside a payment's return re-reads the screen without a payment notice", %{conn: conn} do
    %{conn: conn, account: account} = log_in_paying_user(conn)
    {:ok, view, _html} = live(conn, ~p"/app/billing")

    assert Billing.handle_event(event("checkout.session.completed", checkout_session(account, %{}))) == :ok

    assert has_element?(view, "#billing-status-line", "You have 1 research left.")
    refute has_element?(view, "#payment-received")
  end

  test "coming back from a payment grants nothing by itself", %{conn: conn} do
    %{conn: conn, account: account, user: user} = log_in_paying_user(conn)

    {:ok, view, _html} = live(conn, ~p"/app/billing?paid=1")

    assert has_element?(view, "#billing-status-line", "You have no research left.")
    assert Billing.researches_left(Scope.for_user(user, account)) == 0
  end

  test "an Account that needs no payment sees no payment notice when coming back", %{conn: conn} do
    %{conn: conn} = log_in_user_of(conn, insert(:account, unpaid_access: true))

    {:ok, view, _html} = live(conn, ~p"/app/billing?paid=1")

    refute has_element?(view, "#payment-confirming")
    refute has_element?(view, "#payment-may-be-counted")
  end

  test "the screen never names the internal terms for what was paid", %{conn: conn} do
    %{conn: conn, account: account} = log_in_paying_user(conn)
    insert(:subscription, account: account, status: "past_due")

    {:ok, view, _html} = live(conn, ~p"/app/billing?paid=1")

    text = view |> element("#app-main") |> render() |> LazyHTML.from_fragment() |> LazyHTML.text()
    refute text =~ ~r/allowance|unpaid access|credit|quota|balance|tier|package|trial/i
  end

  test "a signed-out visitor is sent to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/app/billing")

    assert path == ~p"/users/log-in"
  end

  defp log_in_paying_user(conn) do
    account = insert(:account, unpaid_access: false, stripe_customer_id: unique_stripe_customer_id())
    log_in_user_of(conn, account)
  end

  defp log_in_user_of(conn, account) do
    user = insert(:user, memberships: [%Membership{account: account}])
    %{conn: log_in_user(conn, user), account: account, user: user}
  end

  defp subscription_object(account) do
    %{
      "id" => unique_stripe_subscription_id(),
      "object" => "subscription",
      "customer" => account.stripe_customer_id,
      "status" => "active",
      "cancel_at_period_end" => false,
      "cancel_at" => nil,
      "items" => %{"object" => "list", "data" => []}
    }
  end

  defp days_from_now(days), do: :second |> DateTime.utc_now() |> DateTime.shift(day: days)

  defp plain_date(datetime), do: Calendar.strftime(datetime, "%-d %B %Y")
end
