defmodule Dirmoon.Billing.Allowance do
  @moduledoc """
  A number of researches an Account has paid for, one row per payment Stripe
  confirmed (ADR-0004): a Subscription month's researches, valid until that
  month ends, or one Single Research, with no end. A Research Run that spent
  one of them keeps which Allowance it came from. `stripe_reference` is the
  Stripe object the payment was confirmed by, so the same payment is never
  added twice.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Dirmoon.Accounts.Account
  alias Dirmoon.Research.Run

  @sources [:subscription_month, :single_research]

  schema "allowances" do
    field :source, Ecto.Enum, values: @sources
    field :researches, :integer
    field :valid_from, :utc_datetime
    field :valid_until, :utc_datetime
    field :stripe_reference, :string

    belongs_to :account, Account
    has_many :runs, Run

    timestamps(type: :utc_datetime)
  end

  def changeset(%__MODULE__{} = allowance, attrs) do
    allowance
    |> cast(attrs, [:source, :researches, :valid_from, :valid_until, :stripe_reference])
    |> validate_required([:account_id, :source, :researches, :valid_from, :stripe_reference])
    |> validate_number(:researches, greater_than: 0)
    |> check_constraint(:researches, name: :allowances_researches_positive)
    |> foreign_key_constraint(:account_id)
  end
end
