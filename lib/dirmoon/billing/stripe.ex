defmodule Dirmoon.Billing.Stripe do
  @moduledoc """
  The seam to Stripe: its Customer for an Account, its hosted Checkout and
  its customer portal (ADR-0004). The adapter is chosen by `config :dirmoon,
  :stripe_adapter`: `Dirmoon.Billing.Stripe.HTTP` when the secret key and both
  Price ids are set, else `Dirmoon.Billing.Stripe.NotConfigured`.

  Each call answers `{:ok, %{result: result, raw: raw}}`: `raw` is Stripe's
  response body and `result` dirmoon's own shape (atom keys):

    * `create_customer/1`: `%{id: "cus_…"}`, the Customer's id
    * `create_checkout_session/1`: `%{id: "cs_…", url: url}`, the Checkout
      Session and the address of Stripe's checkout page to send the User to
    * `create_portal_session/1`: `%{id: "bps_…", url: url}`, the portal
      session and its short-lived address

  A checkout is for a `:single_research` (a one-off payment) or a
  `:subscription` (the monthly plan); the adapter knows which Stripe Price
  each one is. `success_url` may hold Stripe's literal
  `{CHECKOUT_SESSION_ID}`, which Stripe fills in on the way back.

  Errors: `:not_configured` (no keys), `{:stripe_refused, %{status:, type:,
  code:}}` for a non-2xx answer (`type` and `code` from Stripe's error
  object, nil when the body doesn't carry one), `{:stripe_failed, message}`
  for a 2xx answer without the fields the result is read from, or
  `{:stripe_unreachable, message}` when the request never got an answer.
  """

  @type product :: :single_research | :subscription
  @type account_details :: %{email: String.t(), account_id: pos_integer()}
  @type checkout_request :: %{
          product: product(),
          stripe_customer_id: String.t(),
          account_id: pos_integer(),
          success_url: String.t(),
          cancel_url: String.t()
        }
  @type portal_request :: %{stripe_customer_id: String.t(), return_url: String.t()}
  @type error ::
          :not_configured
          | {:stripe_refused, %{status: pos_integer(), type: String.t() | nil, code: String.t() | nil}}
          | {:stripe_failed, String.t()}
          | {:stripe_unreachable, String.t()}
  @type answer(result) :: {:ok, %{result: result, raw: map()}} | {:error, error()}

  @callback create_customer(account_details()) :: answer(%{id: String.t()})
  @callback create_checkout_session(checkout_request()) :: answer(%{id: String.t(), url: String.t()})
  @callback create_portal_session(portal_request()) :: answer(%{id: String.t(), url: String.t()})

  @doc "Creates the Stripe Customer for an Account, with the User's email."
  @spec create_customer(account_details()) :: answer(%{id: String.t()})
  def create_customer(%{email: email, account_id: account_id} = request) when is_binary(email) and is_integer(account_id),
    do: adapter().create_customer(request)

  @doc "Creates a Checkout Session for one product, for the Account's Stripe Customer."
  @spec create_checkout_session(checkout_request()) :: answer(%{id: String.t(), url: String.t()})
  def create_checkout_session(%{product: product} = request) when product in [:single_research, :subscription],
    do: adapter().create_checkout_session(request)

  @doc "Creates a customer portal session for the Account's Stripe Customer."
  @spec create_portal_session(portal_request()) :: answer(%{id: String.t(), url: String.t()})
  def create_portal_session(%{stripe_customer_id: stripe_customer_id} = request) when is_binary(stripe_customer_id),
    do: adapter().create_portal_session(request)

  defp adapter, do: Application.fetch_env!(:dirmoon, :stripe_adapter)
end
