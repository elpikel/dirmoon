defmodule Dirmoon.Billing.Stripe.NotConfiguredTest do
  use ExUnit.Case, async: true

  alias Dirmoon.Billing.Stripe.NotConfigured

  test "creating a Customer fails because Stripe is not configured" do
    assert NotConfigured.create_customer(%{email: "owner@dirmoon.example", account_id: 1}) == {:error, :not_configured}
  end

  test "creating a checkout fails because Stripe is not configured" do
    request = %{
      product: :single_research,
      stripe_customer_id: "cus_test_1",
      account_id: 1,
      success_url: "https://dirmoon.example/app/billing?paid=1",
      cancel_url: "https://dirmoon.example/app/billing"
    }

    assert NotConfigured.create_checkout_session(request) == {:error, :not_configured}
  end

  test "creating a portal session fails because Stripe is not configured" do
    request = %{stripe_customer_id: "cus_test_1", return_url: "https://dirmoon.example/app/billing"}

    assert NotConfigured.create_portal_session(request) == {:error, :not_configured}
  end
end
