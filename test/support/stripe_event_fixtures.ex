defmodule Dirmoon.StripeEventFixtures do
  @moduledoc """
  Stripe webhook events as Stripe sends them for API version
  `2026-11-18.endive` (JSON-decoded, string keys), and the signed request
  header the webhook expects.
  """
  import Dirmoon.Factory

  def unix_from_now(seconds), do: :second |> DateTime.utc_now() |> DateTime.to_unix() |> Kernel.+(seconds)

  def event(type, object, created \\ unix_from_now(0)) do
    %{
      "id" => unique_stripe_event_id(),
      "object" => "event",
      "api_version" => "2026-11-18.endive",
      "created" => created,
      "type" => type,
      "livemode" => false,
      "pending_webhooks" => 1,
      "request" => %{"id" => nil, "idempotency_key" => nil},
      "data" => %{"object" => object, "previous_attributes" => %{}}
    }
  end

  def checkout_session(account, overrides) do
    Map.merge(
      %{
        "id" => unique_stripe_reference(),
        "object" => "checkout.session",
        "mode" => "payment",
        "status" => "complete",
        "payment_status" => "paid",
        "customer" => account.stripe_customer_id,
        "client_reference_id" => to_string(account.id),
        "subscription" => nil,
        "payment_intent" => "pi_test_single",
        "invoice" => nil,
        "amount_total" => 1000,
        "currency" => "usd",
        "metadata" => %{},
        "livemode" => false
      },
      overrides
    )
  end

  @doc """
  A `Stripe-Signature` header value for `raw_body`, signed at the Unix time
  `timestamp` with `secret` the way Stripe signs: HMAC-SHA256 over
  `"timestamp.raw_body"`, lowercase hex, in a `v1` entry.
  """
  def stripe_signature(raw_body, timestamp, secret) do
    "t=#{timestamp},v1=#{signature_hex(raw_body, timestamp, secret)}"
  end

  def signature_hex(raw_body, timestamp, secret) do
    :hmac |> :crypto.mac(:sha256, secret, "#{timestamp}.#{raw_body}") |> Base.encode16(case: :lower)
  end
end
