defmodule Dirmoon.Accounts.User do
  @moduledoc """
  A person who signs in to dirmoon with a magic link sent to their email.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Dirmoon.Accounts.Membership

  schema "users" do
    field :email, :string
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true

    has_many :memberships, Membership

    timestamps(type: :utc_datetime)
  end

  @doc """
  A user changeset for signing up or changing the email.

  It requires the email to change, otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false to skip the uniqueness query, useful
      for live validations and for sign-up, which never reveals whether an
      email already has a User. A taken email still fails on insert through
      the unique constraint. Defaults to `true`.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
  end

  @doc """
  Confirms the user by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    change(user, confirmed_at: DateTime.utc_now(:second))
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/, message: "must have the @ sign and no spaces")
      |> validate_length(:email, max: 160)
      |> validate_email_changed()

    changeset = unique_constraint(changeset, :email)

    if Keyword.get(opts, :validate_unique, true) do
      unsafe_validate_unique(changeset, :email, Dirmoon.Repo)
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end
end
