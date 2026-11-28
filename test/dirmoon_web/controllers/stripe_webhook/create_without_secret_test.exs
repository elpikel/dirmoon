defmodule DirmoonWeb.Controllers.StripeWebhook.CreateWithoutSecretTest do
  use DirmoonWeb.ConnCase, async: false

  import Dirmoon.StripeEventFixtures

  alias Dirmoon.Billing.StripeEvent
  alias Dirmoon.Repo

  test "without a webhook secret configured the webhook answers 503 and stores nothing", %{conn: conn} do
    configured = Application.fetch_env!(:dirmoon, Dirmoon.Billing)
    Application.put_env(:dirmoon, Dirmoon.Billing, Keyword.delete(configured, :webhook_secret))
    on_exit(fn -> Application.put_env(:dirmoon, Dirmoon.Billing, configured) end)
    event = event("customer.created", %{"id" => unique_stripe_customer_id(), "object" => "customer"})

    conn = signed_post(conn, Jason.encode!(event))

    assert json_response(conn, 503) == %{"error" => "The webhook is not set up yet."}
    refute Repo.get_by(StripeEvent, stripe_event_id: event["id"])
  end

  test "a blank webhook secret counts as not configured", %{conn: conn} do
    configured = Application.fetch_env!(:dirmoon, Dirmoon.Billing)
    Application.put_env(:dirmoon, Dirmoon.Billing, Keyword.put(configured, :webhook_secret, ""))
    on_exit(fn -> Application.put_env(:dirmoon, Dirmoon.Billing, configured) end)
    event = event("customer.created", %{"id" => unique_stripe_customer_id(), "object" => "customer"})

    conn = signed_post(conn, Jason.encode!(event))

    assert json_response(conn, 503) == %{"error" => "The webhook is not set up yet."}
    refute Repo.get_by(StripeEvent, stripe_event_id: event["id"])
  end

  defp signed_post(conn, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("stripe-signature", stripe_signature(body, unix_from_now(0), ""))
    |> post(~p"/webhooks/stripe", body)
  end
end
