defmodule Dirmoon.Accounts.Membership do
  @moduledoc """
  The link between a User and an Account. A User acts in the Account of their
  first Membership.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Dirmoon.Accounts.Account
  alias Dirmoon.Accounts.User

  @primary_key false
  schema "account_memberships" do
    belongs_to :account, Account
    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(membership) do
    membership
    |> change()
    |> assoc_constraint(:account)
    |> assoc_constraint(:user)
    |> unique_constraint([:account_id, :user_id])
  end
end
