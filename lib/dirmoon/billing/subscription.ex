defmodule Dirmoon.Billing.Subscription do
  @moduledoc """
  An Account's monthly plan as Stripe last reported it (ADR-0004), at most
  one per Account: a later Subscription (subscribing again after a
  cancellation) replaces the row.

  `status` is Stripe's own status text, kept as Stripe sends it so a status
  Stripe adds later is still stored; `statuses/0` lists the ones known for
  API version `2026-11-18.endive`. `current_period_start` and
  `current_period_end` are the paid month (empty when the event carried no
  item). `ends_at` is when a scheduled cancellation ends the Subscription,
  nil while it renews. `stripe_updated_at` is the creation time of the
  Stripe event the row was last written from, so an older event delivered
  late never overwrites it.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Dirmoon.Accounts.Account

  @statuses ~w(incomplete incomplete_expired trialing active past_due canceled unpaid paused)
  @ended_statuses ~w(canceled incomplete_expired)
  @paid_statuses ~w(active trialing)
  @payment_failed_statuses ~w(past_due unpaid)
  @fields [:stripe_subscription_id, :status, :current_period_start, :current_period_end, :ends_at, :stripe_updated_at]

  schema "subscriptions" do
    field :stripe_subscription_id, :string
    field :status, :string
    field :current_period_start, :utc_datetime
    field :current_period_end, :utc_datetime
    field :ends_at, :utc_datetime
    field :stripe_updated_at, :utc_datetime

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  @doc "The Subscription statuses Stripe documents, in its order."
  def statuses, do: @statuses

  @doc "The final statuses: a Subscription in one of them has ended for good."
  def ended_statuses, do: @ended_statuses

  @doc """
  Whether the Subscription still exists in Stripe and so rules out a second
  one: every status except the two final ones, `canceled` and
  `incomplete_expired`. `past_due`, `unpaid` and `paused` still run (the
  User fixes or resumes them in the portal), and so does a status Stripe adds
  later, since a second Subscription is the costlier mistake.
  """
  def running?(%__MODULE__{status: status}), do: status not in @ended_statuses

  @doc """
  Whether the Subscription's month is paid and it goes on: `active`, or
  `trialing` (dirmoon offers no such period, but Stripe could report one).
  """
  def paid?(%__MODULE__{status: status}), do: status in @paid_statuses

  @doc """
  Whether Stripe couldn't take the latest payment: `past_due` while it
  retries, `unpaid` once it stopped retrying. The User fixes the card in the
  customer portal.
  """
  def payment_failed?(%__MODULE__{status: status}), do: status in @payment_failed_statuses

  def changeset(%__MODULE__{} = subscription, attrs) do
    subscription
    |> cast(attrs, @fields)
    |> validate_required([:account_id, :stripe_subscription_id, :status, :stripe_updated_at])
    |> unique_constraint(:stripe_subscription_id)
    |> foreign_key_constraint(:account_id)
  end
end
