defmodule Dirmoon.Billing.StripeEvent do
  @moduledoc """
  A Stripe webhook event exactly as received (ADR-0004): its id, type and
  full JSON payload, stored on its first delivery. `processed_at` is set once
  dirmoon has acted on it; an event stored but not processed (it couldn't be
  read) is tried again on the next delivery. The unique `stripe_event_id`
  keeps one row per event.

  `read/2` says what an event means for dirmoon, reading the fields where
  API version `2026-11-18.endive` puts them: a Subscription's period on its
  items (`items.data[].current_period_*`), an invoice's Subscription under
  `parent.subscription_details`, an invoice line's Subscription item under
  `parent.subscription_item_details`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @single_research_types ~w(checkout.session.completed checkout.session.async_payment_succeeded)
  @subscription_month_types ~w(invoice.paid)
  @subscription_types ~w(customer.subscription.created customer.subscription.updated customer.subscription.deleted)
  @read_types @single_research_types ++ @subscription_month_types ++ @subscription_types

  @payment_mode "payment"
  @paid_status "paid"
  @subscription_invoice_parent "subscription_details"
  @subscription_line_parent "subscription_item_details"

  schema "stripe_events" do
    field :stripe_event_id, :string
    field :type, :string
    field :payload, :map
    field :processed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(%{} = payload) do
    %__MODULE__{}
    |> change(stripe_event_id: text(payload["id"]), type: text(payload["type"]), payload: payload)
    |> validate_required([:stripe_event_id, :type, :payload])
  end

  @doc """
  What the event changes, as `{:ok, change}`:

    * `%{change: :single_research, stripe_customer_id:, client_reference_id:,
      stripe_reference:, paid_at:}` for a paid Checkout Session in payment
      mode (`checkout.session.completed` or, for a delayed payment method,
      `checkout.session.async_payment_succeeded`); `paid_at` is the event's
      creation time
    * `%{change: :subscription_month, stripe_customer_id:, stripe_reference:,
      period_start:, period_end:}` for an `invoice.paid` of a Subscription,
      the period of its non-proration Subscription item line that ends last
    * `%{change: :subscription, stripe_customer_id:, subscription: attrs}` for
      `customer.subscription.created`, `.updated` and `.deleted`
    * `%{change: :none}` for anything else: another type, an unpaid or
      Subscription-mode Checkout Session, an invoice not for a Subscription
      or one holding only prorations

  or `{:error, %{change: kind, reason: text}}` when an event of a kind above
  lacks a field it needs (`kind` is that change), or `{:error, %{change:
  :api_version, reason: text}}` when it was rendered with another API
  release than `api_release` (the name after the dot of the pinned version,
  e.g. `"endive"`; Stripe's monthly versions within a release don't break
  fields, so only the release is compared). `reason` names the fields and
  the version, never other values.
  """
  def read(%{"type" => type} = event, api_release) when type in @read_types do
    case release_of(event["api_version"]) do
      ^api_release ->
        read_object(event)

      _other_release ->
        {:error,
         %{
           change: :api_version,
           reason: "rendered with API version #{inspect(event["api_version"])}, not release #{api_release}"
         }}
    end
  end

  def read(_other, _api_release), do: {:ok, %{change: :none}}

  defp read_object(%{"type" => type, "data" => %{"object" => %{} = object}} = event) when type in @single_research_types,
    do: read_checkout(object, event["created"])

  defp read_object(%{"type" => type, "data" => %{"object" => %{} = object}}) when type in @subscription_month_types,
    do: read_invoice(object)

  defp read_object(%{"type" => type, "data" => %{"object" => %{} = object}} = event) when type in @subscription_types,
    do: read_subscription(object, event["created"])

  defp read_object(%{"type" => type}) when type in @single_research_types,
    do: unreadable(:single_research, "a Checkout Session event without its object")

  defp read_object(%{"type" => type}) when type in @subscription_month_types,
    do: unreadable(:subscription_month, "an invoice event without its object")

  defp read_object(%{"type" => type}) when type in @subscription_types,
    do: unreadable(:subscription, "a Subscription event without its object")

  defp release_of(api_version) when is_binary(api_version) do
    case String.split(api_version, ".", parts: 2) do
      [_date, release] -> release
      [_no_release] -> nil
    end
  end

  defp release_of(_missing), do: nil

  defp read_checkout(%{"mode" => @payment_mode, "payment_status" => @paid_status} = session, created) do
    with %{"id" => id, "customer" => stripe_customer_id} when is_binary(id) and is_binary(stripe_customer_id) <- session,
         %DateTime{} = paid_at <- time(created) do
      {:ok,
       %{
         change: :single_research,
         stripe_customer_id: stripe_customer_id,
         client_reference_id: session["client_reference_id"],
         stripe_reference: id,
         paid_at: paid_at
       }}
    else
      _missing -> unreadable(:single_research, "a paid Checkout Session without its id, Customer or event time")
    end
  end

  defp read_checkout(_not_paid, _created), do: {:ok, %{change: :none}}

  defp read_invoice(%{"parent" => %{"type" => @subscription_invoice_parent}} = invoice) do
    with %{"id" => id, "customer" => stripe_customer_id, "lines" => %{"data" => lines}}
         when is_binary(id) and is_binary(stripe_customer_id) and is_list(lines) <- invoice,
         {:ok, periods} <- subscription_line_periods(lines) do
      periods
      |> Enum.max_by(& &1.period_end, DateTime, fn -> nil end)
      |> subscription_month(%{stripe_customer_id: stripe_customer_id, stripe_reference: id})
    else
      _missing -> unreadable(:subscription_month, "a Subscription invoice without its id, Customer or line periods")
    end
  end

  defp read_invoice(_not_for_subscription), do: {:ok, %{change: :none}}

  defp subscription_month(nil, _invoice), do: {:ok, %{change: :none}}

  defp subscription_month(period, invoice),
    do: {:ok, invoice |> Map.merge(period) |> Map.put(:change, :subscription_month)}

  defp subscription_line_periods(lines) do
    lines
    |> Enum.filter(&match?(%{"parent" => %{"type" => @subscription_line_parent}}, &1))
    |> Enum.reject(&match?(%{"parent" => %{"subscription_item_details" => %{"proration" => true}}}, &1))
    |> Enum.reduce_while({:ok, []}, fn line, {:ok, periods} ->
      case line do
        %{"period" => %{"start" => period_start, "end" => period_end}}
        when is_integer(period_start) and is_integer(period_end) ->
          {:cont, {:ok, [%{period_start: time(period_start), period_end: time(period_end)} | periods]}}

        _missing ->
          {:halt, :missing_period}
      end
    end)
  end

  defp read_subscription(object, created) do
    with %{"id" => id, "customer" => stripe_customer_id, "status" => status}
         when is_binary(id) and is_binary(stripe_customer_id) and is_binary(status) <- object,
         %DateTime{} = stripe_updated_at <- time(created) do
      current_period = current_period(object)

      {:ok,
       %{
         change: :subscription,
         stripe_customer_id: stripe_customer_id,
         subscription: %{
           stripe_subscription_id: id,
           status: status,
           current_period_start: current_period.start,
           current_period_end: current_period.end,
           ends_at: ends_at(object, current_period.end),
           stripe_updated_at: stripe_updated_at
         }
       }}
    else
      _missing -> unreadable(:subscription, "a Subscription without its id, Customer, status or event time")
    end
  end

  defp current_period(object) do
    item =
      object
      |> get_in(["items", "data"])
      |> List.wrap()
      |> Enum.filter(&match?(%{"current_period_end" => period_end} when is_integer(period_end), &1))
      |> Enum.max_by(& &1["current_period_end"], fn -> %{} end)

    %{start: time(item["current_period_start"]), end: time(item["current_period_end"])}
  end

  defp ends_at(%{"cancel_at" => cancel_at}, _period_end) when is_integer(cancel_at), do: time(cancel_at)
  defp ends_at(%{"cancel_at_period_end" => true}, period_end), do: period_end
  defp ends_at(_renews, _period_end), do: nil

  defp unreadable(change, reason), do: {:error, %{change: change, reason: reason}}

  defp time(unix_seconds) when is_integer(unix_seconds), do: DateTime.from_unix!(unix_seconds)
  defp time(_missing), do: nil

  defp text(value) when is_binary(value), do: value
  defp text(_missing), do: nil
end
