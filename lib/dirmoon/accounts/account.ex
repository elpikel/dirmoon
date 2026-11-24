defmodule Dirmoon.Accounts.Account do
  @moduledoc """
  The business that uses dirmoon and owns its data: every Research Run,
  Niche, Page and Search Console Connection belongs to one Account (ADR-0001).
  """
  use Ecto.Schema

  alias Dirmoon.Accounts.Membership

  schema "accounts" do
    has_many :memberships, Membership

    timestamps(type: :utc_datetime)
  end
end
