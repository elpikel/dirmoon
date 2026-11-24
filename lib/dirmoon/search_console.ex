defmodule Dirmoon.SearchConsole do
  @moduledoc """
  Search Console Connections: connecting an Account to Google Search Console
  through OAuth, reading and removing its single Connection.

  Every function takes the `Scope` and only sees the Scope's Account's
  Connection (ADR-0001). The Google refresh token is stored encrypted with
  the endpoint's `secret_key_base`; `refresh_token/1` is the only place that
  decrypts it.
  """

  import Ecto.Query

  alias Dirmoon.Accounts.Scope
  alias Dirmoon.Repo
  alias Dirmoon.Research.Run
  alias Dirmoon.SearchConsole.Client
  alias Dirmoon.SearchConsole.Connection

  @refresh_token_salt "search console refresh token"

  @doc """
  The Google consent screen URL for `state`, returning to `redirect_uri`, or
  `{:error, :search_console_not_configured}` without Google credentials.
  """
  def authorize_url(state, redirect_uri) do
    Client.authorize_url(%{state: state, redirect_uri: redirect_uri})
  end

  @doc """
  Exchanges the callback's code and stores the Scope's Account's Connection.
  A reconnect replaces the Connection's email and refresh token.
  """
  def connect(%Scope{account: account}, %{code: code, redirect_uri: redirect_uri}) do
    with {:ok, %{refresh_token: refresh_token, email: email}} <-
           Client.exchange_code(%{code: code, redirect_uri: redirect_uri}) do
      %Connection{account_id: account.id}
      |> Connection.changeset(%{google_email: email, encrypted_refresh_token: encrypt(refresh_token)})
      |> Repo.insert(
        on_conflict: {:replace, [:google_email, :encrypted_refresh_token, :updated_at]},
        conflict_target: :account_id,
        returning: true
      )
    end
  end

  @doc """
  The Scope's Account's Connection, or nil.
  """
  def get_connection(%Scope{} = scope) do
    scope
    |> account_connection_query()
    |> Repo.one()
  end

  @doc """
  The Connection of the run's Account, or nil. Only for the Step 6 worker,
  which has no Scope: the run was already resolved and is never taken from
  params.
  """
  def connection_for_run(%Run{account_id: account_id}) do
    Connection
    |> from(as: :connection)
    |> where([connection: connection], connection.account_id == ^account_id)
    |> Repo.one()
  end

  @doc """
  Whether the Scope's Account has a Connection.
  """
  def connected?(%Scope{} = scope) do
    scope
    |> account_connection_query()
    |> Repo.exists?()
  end

  @doc """
  Removes the Scope's Account's Connection, if any.
  """
  def disconnect(%Scope{} = scope) do
    scope
    |> account_connection_query()
    |> Repo.delete_all()

    :ok
  end

  @doc """
  The Connection's decrypted refresh token, or
  `{:error, :undecryptable_refresh_token}` when it no longer decrypts (for
  example after `secret_key_base` changed), which needs a reconnect.
  """
  def refresh_token(%Connection{encrypted_refresh_token: encrypted_refresh_token}) do
    case Plug.Crypto.decrypt(secret_key_base(), @refresh_token_salt, encrypted_refresh_token, max_age: :infinity) do
      {:ok, refresh_token} when is_binary(refresh_token) -> {:ok, refresh_token}
      _invalid -> {:error, :undecryptable_refresh_token}
    end
  end

  defp account_connection_query(%Scope{account: account}) do
    Connection
    |> from(as: :connection)
    |> where([connection: connection], connection.account_id == ^account.id)
  end

  defp encrypt(refresh_token), do: Plug.Crypto.encrypt(secret_key_base(), @refresh_token_salt, refresh_token)

  defp secret_key_base do
    :dirmoon
    |> Application.fetch_env!(DirmoonWeb.Endpoint)
    |> Keyword.fetch!(:secret_key_base)
  end
end
