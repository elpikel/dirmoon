defmodule Dirmoon.Billing.Stripe.HTTPAutomaticTaxTest do
  use ExUnit.Case, async: false

  alias Dirmoon.Billing.Stripe.HTTP

  test "with automatic tax on, a checkout asks for tax and lets Checkout save the billing address on the Customer" do
    automatic_tax_on()
    test_pid = self()

    Req.Test.stub(HTTP, fn conn ->
      {:ok, raw_body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:form, URI.decode_query(raw_body)})
      Req.Test.json(conn, %{"id" => "cs_test_tax", "url" => "https://checkout.stripe.com/c/pay/cs_test_tax"})
    end)

    HTTP.create_checkout_session(%{
      product: :single_research,
      stripe_customer_id: "cus_test_tax",
      account_id: 5,
      success_url: "https://dirmoon.example/app/billing?paid=1",
      cancel_url: "https://dirmoon.example/app/billing"
    })

    assert_received {:form, %{"automatic_tax[enabled]" => "true", "customer_update[address]" => "auto"}}
  end

  defp automatic_tax_on do
    config = Application.fetch_env!(:dirmoon, HTTP)
    Application.put_env(:dirmoon, HTTP, Keyword.put(config, :automatic_tax, true))
    on_exit(fn -> Application.put_env(:dirmoon, HTTP, config) end)
  end
end
