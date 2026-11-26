defmodule Dirmoon.SearchConsoleTest do
  use Dirmoon.DataCase, async: true

  import Mox

  alias Dirmoon.Accounts
  alias Dirmoon.SearchConsole
  alias Dirmoon.SearchConsole.Client.NotConfigured
  alias Dirmoon.SearchConsole.Connection

  @redirect_uri "http://localhost:4002/app/search-console/callback"

  test "connecting stores the account's connection with the Google email and an encrypted refresh token" do
    scope = scope()
    email = unique_user_email()

    expect(Dirmoon.SearchConsoleMock, :exchange_code, 1, fn %{code: "kod-google", redirect_uri: @redirect_uri} ->
      {:ok, %{refresh_token: "1//refresh-plaintext", access_token: "ya29.access-plaintext", email: email}}
    end)

    assert {:ok, %Connection{} = connection} =
             SearchConsole.connect(scope, %{code: "kod-google", redirect_uri: @redirect_uri})

    stored = Repo.get_by!(Connection, account_id: scope.account.id)
    assert stored.id == connection.id
    assert stored.google_email == email
    refute stored.encrypted_refresh_token =~ "refresh-plaintext"
    assert SearchConsole.refresh_token(stored) == {:ok, "1//refresh-plaintext"}
  end

  test "reconnecting replaces the account's token and email instead of adding a second connection" do
    scope = scope()
    first_email = unique_user_email()
    second_email = unique_user_email()

    stub_exchange(%{refresh_token: "1//first-refresh", email: first_email})
    {:ok, first} = SearchConsole.connect(scope, %{code: "pierwszy", redirect_uri: @redirect_uri})

    stub_exchange(%{refresh_token: "1//second-refresh", email: second_email})
    {:ok, second} = SearchConsole.connect(scope, %{code: "drugi", redirect_uri: @redirect_uri})

    assert [stored] =
             Connection
             |> from(as: :connection)
             |> where([connection: connection], connection.account_id == ^scope.account.id)
             |> Repo.all()

    assert stored.id == first.id
    assert second.id == first.id
    assert stored.google_email == second_email
    assert SearchConsole.refresh_token(stored) == {:ok, "1//second-refresh"}
  end

  test "connecting never replaces another account's connection" do
    other = insert(:search_console_connection, google_email: unique_user_email())
    scope = scope()

    stub_exchange(%{refresh_token: "1//mine", email: unique_user_email()})
    {:ok, mine} = SearchConsole.connect(scope, %{code: "kod", redirect_uri: @redirect_uri})

    untouched = Repo.get!(Connection, other.id)
    assert mine.id != other.id
    assert untouched.google_email == other.google_email
    assert untouched.encrypted_refresh_token == other.encrypted_refresh_token
  end

  test "a failed code exchange stores nothing and returns the reason" do
    scope = scope()

    expect(Dirmoon.SearchConsoleMock, :exchange_code, 1, fn _request -> {:error, :no_refresh_token} end)

    assert SearchConsole.connect(scope, %{code: "kod", redirect_uri: @redirect_uri}) == {:error, :no_refresh_token}
    refute SearchConsole.get_connection(scope)
  end

  test "an account sees only its own connection" do
    connection = insert(:search_console_connection)
    insert(:search_console_connection)
    owner_scope = scope_for_account(connection.account)

    assert SearchConsole.get_connection(owner_scope).id == connection.id
    assert SearchConsole.connected?(owner_scope)
    refute SearchConsole.get_connection(scope())
    refute SearchConsole.connected?(scope())
  end

  test "disconnecting removes only the account's own connection" do
    connection = insert(:search_console_connection)
    other = insert(:search_console_connection)
    scope = scope_for_account(connection.account)

    assert SearchConsole.disconnect(scope) == :ok

    refute Repo.get(Connection, connection.id)
    assert Repo.get(Connection, other.id)
  end

  test "inspecting a connection shows neither the refresh token nor its ciphertext" do
    scope = scope()
    stub_exchange(%{refresh_token: "1//secret-refresh", email: unique_user_email()})
    {:ok, connection} = SearchConsole.connect(scope, %{code: "kod", redirect_uri: @redirect_uri})
    stored = SearchConsole.get_connection(scope)

    for shown <- [inspect(connection), inspect(stored)] do
      refute shown =~ "secret-refresh"
      refute shown =~ stored.encrypted_refresh_token
      refute shown =~ "encrypted_refresh_token"
    end
  end

  test "a run's connection is its own account's and never another account's" do
    connection = insert(:search_console_connection)
    insert(:search_console_connection)
    run = insert(:run, account: connection.account)

    assert SearchConsole.connection_for_run(run).id == connection.id
    refute SearchConsole.connection_for_run(insert(:run))
  end

  test "a token that does not decrypt is reported instead of returned" do
    connection = insert(:search_console_connection, encrypted_refresh_token: "nie-szyfrogram")

    assert SearchConsole.refresh_token(connection) == {:error, :undecryptable_refresh_token}
  end

  test "the authorization url comes from the configured client" do
    expect(Dirmoon.SearchConsoleMock, :authorize_url, 1, fn %{state: "stan", redirect_uri: @redirect_uri} ->
      {:ok, "https://accounts.google.com/o/oauth2/v2/auth?state=stan"}
    end)

    assert SearchConsole.authorize_url("stan", @redirect_uri) ==
             {:ok, "https://accounts.google.com/o/oauth2/v2/auth?state=stan"}
  end

  test "without credentials production and dev both use the not-configured client" do
    production = Config.Reader.read!("config/config.exs", env: :prod)
    dev = Config.Reader.read!("config/config.exs", env: :dev)

    assert get_in(production, [:dirmoon, :search_console_adapter]) == NotConfigured
    assert get_in(dev, [:dirmoon, :search_console_adapter]) == NotConfigured
  end

  defp scope, do: :user |> insert() |> Accounts.scope_for_user()

  defp scope_for_account(account) do
    :membership
    |> insert(account: account)
    |> Map.fetch!(:user)
    |> Accounts.scope_for_user()
  end

  defp stub_exchange(%{refresh_token: refresh_token, email: email}) do
    stub(Dirmoon.SearchConsoleMock, :exchange_code, fn _request ->
      {:ok, %{refresh_token: refresh_token, access_token: "ya29.access", email: email}}
    end)
  end
end
