defmodule Dirmoon.SearchConsole.Connection do
  @moduledoc """
  A Search Console Connection: an Account's authorised access to Google
  Search Console, at most one per Account. The Google refresh token is kept
  only encrypted, and redacted from `inspect/1`; `Dirmoon.SearchConsole`
  encrypts it and is the only place that decrypts it.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Dirmoon.Accounts.Account

  schema "search_console_connections" do
    field :google_email, :string
    field :encrypted_refresh_token, :string, redact: true

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  @doc """
  The Google account's email and the already encrypted refresh token. The
  Account is set by the caller, never cast.
  """
  def changeset(connection, %{google_email: _google_email, encrypted_refresh_token: _encrypted} = attrs) do
    connection
    |> cast(attrs, [:google_email, :encrypted_refresh_token])
    |> validate_required([:google_email, :encrypted_refresh_token])
    |> unique_constraint(:account_id)
  end
end
