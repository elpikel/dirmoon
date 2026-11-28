defmodule Dirmoon.Billing.HandleEventTest do
  use Dirmoon.DataCase, async: true

  import Dirmoon.StripeEventFixtures
  import ExUnit.CaptureLog

  alias Dirmoon.Billing
  alias Dirmoon.Billing.Allowance
  alias Dirmoon.Billing.StripeEvent
  alias Dirmoon.Billing.Subscription

  test "a paid Single Research checkout adds an Allowance of one research with no end" do
    account = paying_account()
    session = checkout_session(account, %{})
    event = event("checkout.session.completed", session, unix_from_now(-60))

    assert Billing.handle_event(event) == :ok

    assert [allowance] = allowances_of(account)

    assert %Allowance{source: :single_research, researches: 1, valid_until: nil} = allowance
    assert allowance.stripe_reference == session["id"]
    assert allowance.valid_from == DateTime.from_unix!(event["created"])
  end

  test "a delayed payment that succeeds later adds the Single Research" do
    account = paying_account()
    session = checkout_session(account, %{})

    assert Billing.handle_event(event("checkout.session.async_payment_succeeded", session)) == :ok

    assert [%Allowance{source: :single_research, researches: 1}] = allowances_of(account)
  end

  test "a paid Subscription invoice adds the month's researches valid for the paid period" do
    account = paying_account()
    period_start = unix_from_now(-60)
    period_end = unix_from_now(30 * 86_400)
    invoice = subscription_invoice(account, [subscription_line(period_start, period_end, false)])

    assert Billing.handle_event(event("invoice.paid", invoice)) == :ok

    assert [allowance] = allowances_of(account)

    assert %Allowance{source: :subscription_month} = allowance
    assert allowance.researches == Billing.offer().monthly_researches
    assert allowance.stripe_reference == invoice["id"]
    assert allowance.valid_from == DateTime.from_unix!(period_start)
    assert allowance.valid_until == DateTime.from_unix!(period_end)
  end

  test "an invoice with several lines is valid for its subscription line that ends last, not for a proration" do
    account = paying_account()
    last_start = unix_from_now(-60)
    last_end = unix_from_now(30 * 86_400)

    invoice =
      subscription_invoice(account, [
        subscription_line(unix_from_now(-30 * 86_400), unix_from_now(-120), false),
        subscription_line(unix_from_now(-600), unix_from_now(60 * 86_400), true),
        subscription_line(last_start, last_end, false)
      ])

    assert Billing.handle_event(event("invoice.paid", invoice)) == :ok

    assert [allowance] = allowances_of(account)
    assert allowance.valid_from == DateTime.from_unix!(last_start)
    assert allowance.valid_until == DateTime.from_unix!(last_end)
  end

  test "a new Subscription is kept with Stripe's status and its current period" do
    account = paying_account()
    period_start = unix_from_now(-60)
    period_end = unix_from_now(30 * 86_400)
    subscription = subscription_object(account, %{"items" => items(period_start, period_end)})
    event = event("customer.subscription.created", subscription)

    assert Billing.handle_event(event) == :ok

    assert %Subscription{status: "active", ends_at: nil} = stored = Repo.get_by!(Subscription, account_id: account.id)
    assert stored.stripe_subscription_id == subscription["id"]
    assert stored.current_period_start == DateTime.from_unix!(period_start)
    assert stored.current_period_end == DateTime.from_unix!(period_end)
    assert stored.stripe_updated_at == DateTime.from_unix!(event["created"])
  end

  test "a Subscription with several items keeps the period of the item that ends last" do
    account = paying_account()
    last_start = unix_from_now(-60)
    last_end = unix_from_now(30 * 86_400)

    items = %{
      "object" => "list",
      "data" => [item(unix_from_now(-600), unix_from_now(86_400)), item(last_start, last_end)]
    }

    event = event("customer.subscription.created", subscription_object(account, %{"items" => items}))

    assert Billing.handle_event(event) == :ok

    assert %Subscription{current_period_start: start, current_period_end: period_end} =
             Repo.get_by!(Subscription, account_id: account.id)

    assert start == DateTime.from_unix!(last_start)
    assert period_end == DateTime.from_unix!(last_end)
  end

  test "a cancellation scheduled in the portal keeps the date the Subscription ends" do
    account = paying_account()
    stored = insert(:subscription, account: account, stripe_updated_at: seconds_ago(3600))
    cancel_at = unix_from_now(20 * 86_400)

    subscription =
      subscription_object(account, %{
        "id" => stored.stripe_subscription_id,
        "cancel_at_period_end" => false,
        "cancel_at" => cancel_at
      })

    assert Billing.handle_event(event("customer.subscription.updated", subscription)) == :ok

    assert Repo.get_by!(Subscription, account_id: account.id).ends_at == DateTime.from_unix!(cancel_at)
  end

  test "a Subscription set to cancel at the period's end ends when its current period ends" do
    account = paying_account()
    period_end = unix_from_now(30 * 86_400)

    subscription =
      subscription_object(account, %{
        "cancel_at_period_end" => true,
        "items" => items(unix_from_now(-60), period_end)
      })

    assert Billing.handle_event(event("customer.subscription.updated", subscription)) == :ok

    assert Repo.get_by!(Subscription, account_id: account.id).ends_at == DateTime.from_unix!(period_end)
  end

  test "a reactivated Subscription no longer has an end" do
    account = paying_account()

    stored =
      insert(:subscription,
        account: account,
        ends_at: DateTime.shift(DateTime.utc_now(:second), day: 20),
        stripe_updated_at: DateTime.from_unix!(unix_from_now(-3600))
      )

    subscription = subscription_object(account, %{"id" => stored.stripe_subscription_id})

    assert Billing.handle_event(event("customer.subscription.updated", subscription)) == :ok

    assert Repo.get_by!(Subscription, account_id: account.id).ends_at == nil
  end

  test "a Subscription that ended is kept as canceled" do
    account = paying_account()

    stored =
      insert(:subscription, account: account, stripe_updated_at: DateTime.from_unix!(unix_from_now(-3600)))

    subscription =
      subscription_object(account, %{"id" => stored.stripe_subscription_id, "status" => "canceled"})

    assert Billing.handle_event(event("customer.subscription.deleted", subscription)) == :ok

    assert %Subscription{status: "canceled"} = Repo.get_by!(Subscription, account_id: account.id)
  end

  test "a new Subscription after a cancelled one replaces it on the Account" do
    account = paying_account()

    insert(:subscription,
      account: account,
      status: "canceled",
      stripe_updated_at: DateTime.from_unix!(unix_from_now(-3600))
    )

    subscription = subscription_object(account, %{})

    assert Billing.handle_event(event("customer.subscription.created", subscription)) == :ok

    assert [%Subscription{status: "active", stripe_subscription_id: stripe_subscription_id}] =
             subscriptions_of(account)

    assert stripe_subscription_id == subscription["id"]
  end

  test "every event is stored with its id, type and full payload as received" do
    account = paying_account()
    event = event("checkout.session.completed", checkout_session(account, %{}))

    assert Billing.handle_event(event) == :ok

    assert %StripeEvent{type: "checkout.session.completed", payload: payload} =
             Repo.get_by!(StripeEvent, stripe_event_id: event["id"])

    assert payload == event
  end

  test "an event type dirmoon doesn't use is stored and changes nothing else" do
    account = paying_account()
    event = event("customer.updated", %{"id" => account.stripe_customer_id, "object" => "customer"})

    assert Billing.handle_event(event) == :ok

    assert %StripeEvent{type: "customer.updated"} = Repo.get_by!(StripeEvent, stripe_event_id: event["id"])
    assert allowances_of(account) == []
    assert Repo.get_by(Subscription, account_id: account.id) == nil
  end

  test "an event delivered twice is stored once and adds one Allowance" do
    account = paying_account()
    event = event("checkout.session.completed", checkout_session(account, %{}))

    assert Billing.handle_event(event) == :ok
    assert Billing.handle_event(event) == :ok

    assert [_allowance] = allowances_of(account)
    assert [_stored] = stored_events(event)
  end

  test "two events for the same paid checkout add one Allowance" do
    account = paying_account()
    session = checkout_session(account, %{})

    assert Billing.handle_event(event("checkout.session.completed", session)) == :ok
    assert Billing.handle_event(event("checkout.session.async_payment_succeeded", session)) == :ok

    assert [_allowance] = allowances_of(account)
  end

  test "a checkout whose payment hasn't arrived yet adds nothing" do
    account = paying_account()
    session = checkout_session(account, %{"payment_status" => "unpaid"})

    assert Billing.handle_event(event("checkout.session.completed", session)) == :ok

    assert allowances_of(account) == []
  end

  test "a completed Subscription checkout adds nothing, since its paid invoice does" do
    account = paying_account()

    session =
      checkout_session(account, %{
        "mode" => "subscription",
        "subscription" => unique_stripe_subscription_id(),
        "payment_intent" => nil
      })

    assert Billing.handle_event(event("checkout.session.completed", session)) == :ok

    assert allowances_of(account) == []
  end

  test "a paid checkout dirmoon didn't open for the Account adds nothing" do
    account = paying_account()
    other_account = insert(:account, unpaid_access: false)
    session = checkout_session(account, %{"client_reference_id" => to_string(other_account.id)})

    assert Billing.handle_event(event("checkout.session.completed", session)) == :ok

    assert allowances_of(account) == []
    assert allowances_of(other_account) == []
  end

  test "a paid invoice that is not for a Subscription adds nothing" do
    account = paying_account()
    invoice = Map.put(subscription_invoice(account, []), "parent", nil)

    assert Billing.handle_event(event("invoice.paid", invoice)) == :ok

    assert allowances_of(account) == []
  end

  test "a paid Subscription invoice with only prorations adds nothing" do
    account = paying_account()
    invoice = subscription_invoice(account, [subscription_line(unix_from_now(-60), unix_from_now(86_400), true)])

    assert Billing.handle_event(event("invoice.paid", invoice)) == :ok

    assert allowances_of(account) == []
  end

  test "an older Subscription event arriving late doesn't overwrite a newer state" do
    account = paying_account()
    newer = DateTime.from_unix!(unix_from_now(-60))
    stored = insert(:subscription, account: account, status: "canceled", stripe_updated_at: newer)
    subscription = subscription_object(account, %{"id" => stored.stripe_subscription_id, "status" => "active"})

    assert Billing.handle_event(event("customer.subscription.updated", subscription, unix_from_now(-3600))) == :ok

    assert %Subscription{status: "canceled", stripe_updated_at: ^newer} =
             Repo.get_by!(Subscription, account_id: account.id)
  end

  test "an event for a Stripe Customer of no Account is stored and changes nothing else" do
    account = paying_account()
    paid_line = subscription_line(unix_from_now(-60), unix_from_now(86_400), false)

    events = [
      event("checkout.session.completed", checkout_session(account, %{"customer" => unique_stripe_customer_id()})),
      event("invoice.paid", %{subscription_invoice(account, [paid_line]) | "customer" => unique_stripe_customer_id()}),
      event("customer.subscription.created", subscription_object(account, %{"customer" => unique_stripe_customer_id()}))
    ]

    assert Enum.map(events, &Billing.handle_event/1) == [:ok, :ok, :ok]

    assert events |> Enum.flat_map(&stored_events/1) |> length() == 3
    assert allowances_of(account) == []
    assert subscriptions_of(account) == []
  end

  test "a Subscription event without items keeps the Subscription without a period" do
    account = paying_account()
    subscription = Map.delete(subscription_object(account, %{}), "items")

    assert Billing.handle_event(event("customer.subscription.created", subscription)) == :ok

    assert %Subscription{status: "active", current_period_start: nil, current_period_end: nil} =
             Repo.get_by!(Subscription, account_id: account.id)
  end

  test "a processed event delivered again changes nothing, even with a different payload" do
    account = paying_account()
    event = event("checkout.session.completed", checkout_session(account, %{}))

    assert Billing.handle_event(event) == :ok

    second_delivery = put_in(event, ["data", "object", "id"], unique_stripe_reference())

    assert Billing.handle_event(second_delivery) == :ok

    assert [_one_allowance] = allowances_of(account)
    assert %StripeEvent{payload: ^event} = Repo.get_by!(StripeEvent, stripe_event_id: event["id"])
  end

  test "an event acted on is marked processed" do
    account = paying_account()
    event = event("customer.updated", %{"id" => account.stripe_customer_id, "object" => "customer"})

    assert Billing.handle_event(event) == :ok

    assert %StripeEvent{processed_at: %DateTime{}} = Repo.get_by!(StripeEvent, stripe_event_id: event["id"])
  end

  test "a Subscription event for a cancelled duplicate doesn't overwrite the Subscription still running" do
    account = paying_account()
    running = insert(:subscription, account: account, status: "active", stripe_updated_at: seconds_ago(3600))
    duplicate = subscription_object(account, %{"status" => "canceled"})

    assert Billing.handle_event(event("customer.subscription.deleted", duplicate)) == :ok

    assert [%Subscription{status: "active", stripe_subscription_id: stripe_subscription_id}] = subscriptions_of(account)
    assert stripe_subscription_id == running.stripe_subscription_id
  end

  test "an old active event for another id, older than the stored cancelled row, doesn't replace it" do
    account = paying_account()
    cancelled = insert(:subscription, account: account, status: "canceled", stripe_updated_at: seconds_ago(60))
    stale = subscription_object(account, %{})

    assert Billing.handle_event(event("customer.subscription.created", stale, unix_from_now(-3600))) == :ok

    assert [%Subscription{status: "canceled", stripe_subscription_id: stripe_subscription_id}] = subscriptions_of(account)
    assert stripe_subscription_id == cancelled.stripe_subscription_id
  end

  test "an event from a later monthly version of the same API release is read" do
    account = paying_account()
    event = %{event("checkout.session.completed", checkout_session(account, %{})) | "api_version" => "2026-09-30.endive"}

    assert Billing.handle_event(event) == :ok

    assert [_allowance] = allowances_of(account)
  end

  @tag :capture_log
  test "a paid checkout without its Customer is kept unprocessed and applied once a delivery can be read" do
    account = paying_account()
    readable = event("checkout.session.completed", checkout_session(account, %{}))
    unreadable = put_in(readable, ["data", "object", "customer"], nil)

    log = capture_log(fn -> assert Billing.handle_event(unreadable) == {:error, :unreadable_event} end)

    assert log =~ readable["id"]
    assert %StripeEvent{processed_at: nil, payload: ^unreadable} = stored_event(readable)
    assert allowances_of(account) == []

    assert Billing.handle_event(readable) == :ok
    assert Billing.handle_event(readable) == :ok

    assert [_one_allowance] = allowances_of(account)
    assert %StripeEvent{processed_at: %DateTime{}} = stored_event(readable)
  end

  @tag :capture_log
  test "a paid Subscription invoice without a readable line is kept unprocessed and applied once readable" do
    account = paying_account()

    readable =
      event(
        "invoice.paid",
        subscription_invoice(account, [subscription_line(unix_from_now(-60), unix_from_now(86_400), false)])
      )

    unreadable =
      put_in(readable, ["data", "object", "lines", "data"], [%{"parent" => %{"type" => "subscription_item_details"}}])

    log = capture_log(fn -> assert Billing.handle_event(unreadable) == {:error, :unreadable_event} end)

    assert log =~ readable["id"]
    refute log =~ account.stripe_customer_id
    assert %StripeEvent{processed_at: nil} = stored_event(readable)

    assert Billing.handle_event(readable) == :ok
    assert Billing.handle_event(readable) == :ok

    assert [%Allowance{source: :subscription_month}] = allowances_of(account)
  end

  @tag :capture_log
  test "a paid month rendered with an older API release is kept unprocessed and refused" do
    account = paying_account()
    invoice = Map.delete(subscription_invoice(account, []), "parent")
    event = %{event("invoice.paid", invoice) | "api_version" => "2025-02-24.acacia"}

    log = capture_log(fn -> assert Billing.handle_event(event) == {:error, :unreadable_event} end)

    assert log =~ event["id"]
    assert log =~ "2025-02-24.acacia"
    assert %StripeEvent{processed_at: nil} = stored_event(event)
  end

  @tag :capture_log
  test "a Subscription event rendered with a version without a release name is refused" do
    account = paying_account()
    event = %{event("customer.subscription.updated", subscription_object(account, %{})) | "api_version" => "2024-06-20"}

    capture_log(fn -> assert Billing.handle_event(event) == {:error, :unreadable_event} end)

    assert subscriptions_of(account) == []
  end

  @tag :capture_log
  test "a Checkout Session event without an API version is refused" do
    account = paying_account()
    event = Map.delete(event("checkout.session.completed", checkout_session(account, %{})), "api_version")

    capture_log(fn -> assert Billing.handle_event(event) == {:error, :unreadable_event} end)

    assert allowances_of(account) == []
  end

  @tag :capture_log
  test "a Checkout Session event without its object is kept unprocessed and refused" do
    event = %{event("checkout.session.completed", %{}) | "data" => %{}}

    log = capture_log(fn -> assert Billing.handle_event(event) == {:error, :unreadable_event} end)

    assert log =~ "without its object"
    assert %StripeEvent{processed_at: nil} = stored_event(event)
  end

  @tag :capture_log
  test "an invoice event whose object is not an invoice is kept unprocessed and refused" do
    event = %{event("invoice.paid", %{}) | "data" => %{"object" => "in_test_not_expanded"}}

    capture_log(fn -> assert Billing.handle_event(event) == {:error, :unreadable_event} end)

    assert %StripeEvent{processed_at: nil} = stored_event(event)
  end

  @tag :capture_log
  test "a Subscription event without its object is processed with no change" do
    event = %{event("customer.subscription.updated", %{}) | "data" => %{}}

    capture_log(fn -> assert Billing.handle_event(event) == :ok end)

    assert %StripeEvent{processed_at: %DateTime{}} = stored_event(event)
  end

  @tag :capture_log
  test "a paid Subscription invoice without its lines is refused" do
    account = paying_account()
    invoice = Map.delete(subscription_invoice(account, []), "lines")

    event = event("invoice.paid", invoice)

    capture_log(fn -> assert Billing.handle_event(event) == {:error, :unreadable_event} end)

    assert allowances_of(account) == []
  end

  @tag :capture_log
  test "a Subscription event without its status is stored, logged and changes nothing else" do
    account = paying_account()
    event = event("customer.subscription.updated", Map.delete(subscription_object(account, %{}), "status"))

    log = capture_log(fn -> assert Billing.handle_event(event) == :ok end)

    assert log =~ event["id"]
    assert %StripeEvent{} = Repo.get_by!(StripeEvent, stripe_event_id: event["id"])
    assert Repo.get_by(Subscription, account_id: account.id) == nil
  end

  @tag :capture_log
  test "an event without an id is refused" do
    event = Map.delete(event("customer.updated", %{}), "id")

    log = capture_log(fn -> assert Billing.handle_event(event) == {:error, :unreadable_event} end)

    assert log =~ "without an id or type"
    assert Repo.aggregate(StripeEvent, :count) == 0
  end

  defp paying_account, do: insert(:account, unpaid_access: false, stripe_customer_id: unique_stripe_customer_id())

  defp allowances_of(account) do
    Allowance
    |> from(as: :allowance)
    |> where([allowance: allowance], allowance.account_id == ^account.id)
    |> Repo.all()
  end

  defp subscriptions_of(account) do
    Subscription
    |> from(as: :subscription)
    |> where([subscription: subscription], subscription.account_id == ^account.id)
    |> Repo.all()
  end

  defp stored_event(%{"id" => stripe_event_id}), do: Repo.get_by!(StripeEvent, stripe_event_id: stripe_event_id)

  defp seconds_ago(seconds), do: DateTime.from_unix!(unix_from_now(-seconds))

  defp stored_events(%{"id" => stripe_event_id}) do
    StripeEvent
    |> from(as: :stripe_event)
    |> where([stripe_event: stripe_event], stripe_event.stripe_event_id == ^stripe_event_id)
    |> Repo.all()
  end

  defp subscription_invoice(account, lines) do
    stripe_subscription_id = unique_stripe_subscription_id()

    %{
      "id" => unique_stripe_invoice_id(),
      "object" => "invoice",
      "customer" => account.stripe_customer_id,
      "status" => "paid",
      "billing_reason" => "subscription_cycle",
      "currency" => "usd",
      "amount_paid" => 4900,
      "total" => 4900,
      "period_start" => unix_from_now(-30 * 86_400),
      "period_end" => unix_from_now(-60),
      "parent" => %{
        "type" => "subscription_details",
        "quote_details" => nil,
        "subscription_details" => %{"subscription" => stripe_subscription_id, "metadata" => %{}}
      },
      "lines" => %{"object" => "list", "has_more" => false, "data" => lines}
    }
  end

  defp subscription_line(period_start, period_end, proration?) do
    %{
      "id" => "il_test_line",
      "object" => "line_item",
      "amount" => 4900,
      "currency" => "usd",
      "period" => %{"start" => period_start, "end" => period_end},
      "parent" => %{
        "type" => "subscription_item_details",
        "invoice_item_details" => nil,
        "subscription_item_details" => %{
          "subscription" => "sub_test_line",
          "subscription_item" => "si_test_line",
          "proration" => proration?
        }
      },
      "pricing" => %{
        "type" => "price_details",
        "price_details" => %{"price" => "price_test_monthly", "product" => "prod_test_monthly"}
      }
    }
  end

  defp subscription_object(account, overrides) do
    Map.merge(
      %{
        "id" => unique_stripe_subscription_id(),
        "object" => "subscription",
        "customer" => account.stripe_customer_id,
        "status" => "active",
        "cancel_at_period_end" => false,
        "cancel_at" => nil,
        "canceled_at" => nil,
        "ended_at" => nil,
        "billing_cycle_anchor" => unix_from_now(-60),
        "latest_invoice" => unique_stripe_invoice_id(),
        "metadata" => %{},
        "items" => items(unix_from_now(-60), unix_from_now(30 * 86_400))
      },
      overrides
    )
  end

  defp items(period_start, period_end), do: %{"object" => "list", "data" => [item(period_start, period_end)]}

  defp item(period_start, period_end) do
    %{
      "id" => "si_test_item",
      "object" => "subscription_item",
      "current_period_start" => period_start,
      "current_period_end" => period_end,
      "price" => %{"id" => "price_test_monthly", "recurring" => %{"interval" => "month"}},
      "quantity" => 1
    }
  end
end
