defmodule Dirmoon.Billing.Stripe.HTTP do
  @moduledoc """
  The Stripe adapter over HTTP (Req): one form-encoded `POST` per call to
  `/v1/customers`, `/v1/checkout/sessions` or `/v1/billing_portal/sessions`,
  with the secret key as a Bearer token and the API version pinned by the
  `Stripe-Version` header. A failed request is not retried here.

  Configured by `config :dirmoon, Dirmoon.Billing.Stripe.HTTP` with
  `secret_key`, `single_price_id` (the Single Research's one-off Price),
  `monthly_price_id` (the Subscription's monthly Price), `api_version`,
  `base_url`, `automatic_tax` (Stripe Tax on the checkout; off by default)
  and extra `req_options`. The key travels only in the `Authorization`
  header and is never in a result or an error. Stripe's answer is awaited
  for up to 30 seconds.

  Creating a Customer sends an `Idempotency-Key` made from the Account id, so
  a repeat within Stripe's 24 hours returns the same Customer instead of a
  second one. A checkout never sends `payment_method_types` (refused since
  `2026-09-30.endive`; the Dashboard's payment methods apply) and asks for no
  post-purchase invoice. With `automatic_tax` on it also sends
  `customer_update[address]=auto`, so the billing address Checkout collects
  is saved on the Customer and taxed.

  Stripe documents its error object's fields (`type`, `code`, …) but not, on
  the pages read, that the body wraps it under `"error"`; an error body is
  read that way when it has that shape, and only its `type` and `code` are
  kept.
  """

  @behaviour Dirmoon.Billing.Stripe

  alias Dirmoon.Billing.Stripe

  @default_base_url "https://api.stripe.com"
  @receive_timeout 30_000
  @checkout_modes %{single_research: "payment", subscription: "subscription"}
  @price_id_keys %{single_research: :single_price_id, subscription: :monthly_price_id}

  @impl Stripe
  def create_customer(%{email: email, account_id: account_id}) do
    "/v1/customers"
    |> post(
      [{"email", email}, {"metadata[account_id]", to_string(account_id)}],
      [{"idempotency-key", "dirmoon-account-#{account_id}-stripe-customer"}]
    )
    |> answer(["id"])
  end

  @impl Stripe
  def create_checkout_session(%{product: product} = request) do
    config = config()

    form =
      [
        {"mode", Map.fetch!(@checkout_modes, product)},
        {"customer", request.stripe_customer_id},
        {"client_reference_id", to_string(request.account_id)},
        {"line_items[0][price]", Keyword.fetch!(config, Map.fetch!(@price_id_keys, product))},
        {"line_items[0][quantity]", "1"},
        {"success_url", request.success_url},
        {"cancel_url", request.cancel_url}
      ] ++ tax_fields(Keyword.get(config, :automatic_tax, false))

    "/v1/checkout/sessions"
    |> post(form, [])
    |> answer(["id", "url"])
  end

  @impl Stripe
  def create_portal_session(%{stripe_customer_id: stripe_customer_id, return_url: return_url}) do
    "/v1/billing_portal/sessions"
    |> post([{"customer", stripe_customer_id}, {"return_url", return_url}], [])
    |> answer(["id", "url"])
  end

  defp tax_fields(true), do: [{"automatic_tax[enabled]", "true"}, {"customer_update[address]", "auto"}]
  defp tax_fields(false), do: [{"automatic_tax[enabled]", "false"}]

  defp post(path, form, headers) do
    config = config()

    Req.request(
      [
        method: :post,
        base_url: Keyword.get(config, :base_url, @default_base_url),
        url: path,
        auth: {:bearer, Keyword.fetch!(config, :secret_key)},
        headers: [{"stripe-version", Keyword.fetch!(config, :api_version)} | headers],
        form: form,
        receive_timeout: @receive_timeout,
        retry: false
      ],
      Keyword.get(config, :req_options, [])
    )
  end

  defp answer({:ok, %Req.Response{status: status, body: body}}, fields) when status in 200..299 do
    case result(body, fields) do
      %{} = result -> {:ok, %{result: result, raw: body}}
      nil -> {:error, {:stripe_failed, "answer without " <> Enum.join(fields, " or ")}}
    end
  end

  defp answer({:ok, %Req.Response{status: status, body: %{"error" => %{} = error}}}, _fields),
    do: {:error, {:stripe_refused, %{status: status, type: text(error["type"]), code: text(error["code"])}}}

  defp answer({:ok, %Req.Response{status: status}}, _fields),
    do: {:error, {:stripe_refused, %{status: status, type: nil, code: nil}}}

  defp answer({:error, exception}, _fields), do: {:error, {:stripe_unreachable, Exception.message(exception)}}

  defp result(%{} = body, fields) do
    values = Map.take(body, fields)

    if map_size(values) == length(fields) and Enum.all?(Map.values(values), &is_binary/1) do
      Map.new(values, fn {field, value} -> {String.to_existing_atom(field), value} end)
    end
  end

  defp result(_not_json, _fields), do: nil

  defp text(value) when is_binary(value), do: value
  defp text(_missing), do: nil

  defp config, do: Application.get_env(:dirmoon, __MODULE__, [])
end
