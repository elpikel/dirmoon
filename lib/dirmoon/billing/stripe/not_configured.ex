defmodule Dirmoon.Billing.Stripe.NotConfigured do
  @moduledoc """
  The Stripe adapter used when the secret key or a Price id is missing:
  every call fails with `:not_configured` and nothing is sent to Stripe.
  """

  @behaviour Dirmoon.Billing.Stripe

  alias Dirmoon.Billing.Stripe

  @impl Stripe
  def create_customer(_request), do: {:error, :not_configured}

  @impl Stripe
  def create_checkout_session(_request), do: {:error, :not_configured}

  @impl Stripe
  def create_portal_session(_request), do: {:error, :not_configured}
end
