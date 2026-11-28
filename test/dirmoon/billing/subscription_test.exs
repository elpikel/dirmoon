defmodule Dirmoon.Billing.SubscriptionTest do
  use ExUnit.Case, async: true

  alias Dirmoon.Billing.Subscription

  test "a Subscription still runs in every Stripe status but canceled and incomplete_expired" do
    running = Enum.filter(Subscription.statuses(), &Subscription.running?(%Subscription{status: &1}))

    assert running == ~w(incomplete trialing active past_due unpaid paused)
  end

  test "a Subscription in a status Stripe adds later counts as still running" do
    assert Subscription.running?(%Subscription{status: "some_new_status"})
  end

  test "a Subscription is paid while active, or trialing should Stripe report it" do
    paid = Enum.filter(Subscription.statuses(), &Subscription.paid?(%Subscription{status: &1}))

    assert paid == ~w(trialing active)
  end

  test "a Subscription's payment failed while past_due or unpaid" do
    failed = Enum.filter(Subscription.statuses(), &Subscription.payment_failed?(%Subscription{status: &1}))

    assert failed == ~w(past_due unpaid)
  end
end
