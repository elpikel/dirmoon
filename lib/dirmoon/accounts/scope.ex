defmodule Dirmoon.Accounts.Scope do
  @moduledoc """
  The caller of a context function: the signed-in User and the Account they
  act in, which is the Account of their first Membership (ADR-0001).

  Every per-Account context function takes the Scope and filters by
  `scope.account`.
  """

  alias Dirmoon.Accounts.Account
  alias Dirmoon.Accounts.User

  defstruct user: nil, account: nil

  @doc """
  Creates a scope for the given user acting in the given Account.
  """
  def for_user(%User{} = user, %Account{} = account) do
    %__MODULE__{user: user, account: account}
  end
end
