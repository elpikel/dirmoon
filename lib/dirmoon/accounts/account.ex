defmodule Dirmoon.Accounts.Account do
  @moduledoc """
  The business that uses dirmoon and owns its data: every Research Run,
  Niche, Page and Search Console Connection belongs to one Account (ADR-0001).
  It pays through its Allowances, unless it has Unpaid Access (ADR-0004);
  `stripe_customer_id` is its Stripe Customer, once one is created.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Dirmoon.Accounts.Membership
  alias Dirmoon.Billing.Allowance

  schema "accounts" do
    field :unpaid_access, :boolean, default: false
    field :stripe_customer_id, :string

    has_many :memberships, Membership
    has_many :allowances, Allowance

    timestamps(type: :utc_datetime)
  end

  def unpaid_access_changeset(%__MODULE__{} = account, unpaid?) when is_boolean(unpaid?) do
    change(account, unpaid_access: unpaid?)
  end
end
