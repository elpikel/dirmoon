defmodule Dirmoon.Billing.StripeTest do
  use ExUnit.Case, async: false

  import Mox

  alias Dirmoon.Billing.Stripe

  @stripe_variables ["STRIPE_SECRET_KEY", "STRIPE_PRICE_SINGLE", "STRIPE_PRICE_MONTHLY", "STRIPE_WEBHOOK_SECRET"]

  test "creating a Customer goes to the configured adapter" do
    request = %{email: "owner@dirmoon.example", account_id: 3}
    expect(Dirmoon.StripeMock, :create_customer, 1, fn ^request -> {:ok, %{result: %{id: "cus_test_1"}, raw: %{}}} end)

    assert {:ok, %{result: %{id: "cus_test_1"}}} = Stripe.create_customer(request)
  end

  test "creating a checkout goes to the configured adapter" do
    request = %{
      product: :subscription,
      stripe_customer_id: "cus_test_1",
      account_id: 3,
      success_url: "https://dirmoon.example/app/billing?paid=1",
      cancel_url: "https://dirmoon.example/app/billing"
    }

    expect(Dirmoon.StripeMock, :create_checkout_session, 1, fn ^request ->
      {:ok, %{result: %{id: "cs_test_1", url: "https://checkout.stripe.com/c/pay/cs_test_1"}, raw: %{}}}
    end)

    assert {:ok, %{result: %{id: "cs_test_1"}}} = Stripe.create_checkout_session(request)
  end

  test "creating a portal session goes to the configured adapter" do
    request = %{stripe_customer_id: "cus_test_1", return_url: "https://dirmoon.example/app/billing"}

    expect(Dirmoon.StripeMock, :create_portal_session, 1, fn ^request ->
      {:ok, %{result: %{id: "bps_test_1", url: "https://billing.stripe.com/p/session/test_1"}, raw: %{}}}
    end)

    assert {:ok, %{result: %{id: "bps_test_1"}}} = Stripe.create_portal_session(request)
  end

  test "without keys every environment uses the not-configured adapter with automatic tax off" do
    for env <- [:prod, :dev] do
      config = Config.Reader.read!("config/config.exs", env: env)

      assert get_in(config, [:dirmoon, :stripe_adapter]) == Stripe.NotConfigured
      assert get_in(config, [:dirmoon, Stripe.HTTP, :automatic_tax]) == false
    end
  end

  test "the secret key and both prices in the env vars switch to the HTTP adapter with them" do
    config =
      runtime_config(%{
        "STRIPE_SECRET_KEY" => "sk_test_env",
        "STRIPE_PRICE_SINGLE" => "price_env_single",
        "STRIPE_PRICE_MONTHLY" => "price_env_monthly"
      })

    assert get_in(config, [:dirmoon, :stripe_adapter]) == Stripe.HTTP

    assert get_in(config, [:dirmoon, Stripe.HTTP]) == [
             secret_key: "sk_test_env",
             single_price_id: "price_env_single",
             monthly_price_id: "price_env_monthly"
           ]
  end

  test "a missing price keeps the not-configured adapter" do
    config = runtime_config(%{"STRIPE_SECRET_KEY" => "sk_test_env", "STRIPE_PRICE_SINGLE" => "price_env_single"})

    assert get_in(config, [:dirmoon, :stripe_adapter]) == nil
  end

  test "a blank secret key keeps the not-configured adapter" do
    config =
      runtime_config(%{
        "STRIPE_SECRET_KEY" => "",
        "STRIPE_PRICE_SINGLE" => "price_env_single",
        "STRIPE_PRICE_MONTHLY" => "price_env_monthly"
      })

    assert get_in(config, [:dirmoon, :stripe_adapter]) == nil
  end

  test "the webhook secret in its env var is kept for the webhook, and a blank one is not" do
    assert get_in(runtime_config(%{"STRIPE_WEBHOOK_SECRET" => "whsec_env"}), [:dirmoon, Dirmoon.Billing, :webhook_secret]) ==
             "whsec_env"

    assert get_in(runtime_config(%{"STRIPE_WEBHOOK_SECRET" => ""}), [:dirmoon, Dirmoon.Billing]) == nil
  end

  defp runtime_config(variables) do
    previous = Map.new(@stripe_variables, &{&1, System.get_env(&1)})
    Enum.each(@stripe_variables, &System.delete_env/1)
    System.put_env(variables)

    try do
      Config.Reader.read!("config/runtime.exs", env: :dev)
    after
      Enum.each(previous, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end
  end
end
