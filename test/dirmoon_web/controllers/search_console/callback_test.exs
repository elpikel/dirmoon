defmodule DirmoonWeb.Controllers.SearchConsole.CallbackTest do
  use DirmoonWeb.ConnCase, async: true

  import Mox

  alias Dirmoon.Repo
  alias Dirmoon.SearchConsole
  alias Dirmoon.SearchConsole.Connection

  test "granting access at Google stores the account's connection with an encrypted refresh token", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    email = unique_user_email()
    callback_url = url(~p"/app/search-console/callback")
    %{conn: conn, state: state} = start_connect(conn)

    expect(Dirmoon.SearchConsoleMock, :exchange_code, 1, fn %{code: "4/kod-google", redirect_uri: ^callback_url} ->
      {:ok, %{refresh_token: "1//refresh-plaintext", access_token: "ya29.access-plaintext", email: email}}
    end)

    get(conn, ~p"/app/search-console/callback?#{[code: "4/kod-google", state: state]}")

    connection = Repo.get_by!(Connection, account_id: scope.account.id)
    assert connection.google_email == email
    refute connection.encrypted_refresh_token =~ "refresh-plaintext"
    assert SearchConsole.refresh_token(connection) == {:ok, "1//refresh-plaintext"}
  end

  test "after connecting the user is back in the app and sees which Google account was connected", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    email = unique_user_email()
    %{conn: conn, state: state} = start_connect(conn)
    stub_exchange(email)

    conn = get(conn, ~p"/app/search-console/callback?#{[code: "4/kod", state: state]}")

    assert redirected_to(conn) == ~p"/app"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Połączono z Search Console (#{email})"
  end

  test "after connecting the user returns to the app page they started from", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    %{conn: conn, state: state} = start_connect(conn, %{return_to: "/app/runs/7"})
    stub_exchange(unique_user_email())

    conn = get(conn, ~p"/app/search-console/callback?#{[code: "4/kod", state: state]}")

    assert redirected_to(conn) == "/app/runs/7"
  end

  test "after connecting the user returns to the app page they started from, query string included", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    %{conn: conn, state: state} = start_connect(conn, %{return_to: "/app/runs/1?view=niches"})
    stub_exchange(unique_user_email())

    conn = get(conn, ~p"/app/search-console/callback?#{[code: "4/kod", state: state]}")

    assert redirected_to(conn) == "/app/runs/1?view=niches"
  end

  test "neither the flash nor the redirect carries a token", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    %{conn: conn, state: state} = start_connect(conn)
    stub_exchange(unique_user_email())

    conn = get(conn, ~p"/app/search-console/callback?#{[code: "4/kod", state: state]}")

    shown = redirected_to(conn) <> inspect(conn.assigns.flash) <> inspect(get_session(conn))
    refute shown =~ "refresh-plaintext"
    refute shown =~ "access-plaintext"
  end

  test "a callback with a state not issued to this session stores nothing and shows an error", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    %{conn: conn} = start_connect(conn)

    conn = get(conn, ~p"/app/search-console/callback?#{[code: "4/kod", state: "podrobiony-stan"]}")

    assert redirected_to(conn) == ~p"/app"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Nie udało się połączyć z Search Console"
    refute SearchConsole.get_connection(scope)
  end

  test "a callback with no state issued to this session stores nothing and shows an error", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})

    conn = get(conn, ~p"/app/search-console/callback?#{[code: "4/kod", state: "jakis-stan"]}")

    assert redirected_to(conn) == ~p"/app"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Nie udało się połączyć z Search Console"
    refute SearchConsole.get_connection(scope)
  end

  test "a callback without a state stores nothing and shows an error", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    %{conn: conn} = start_connect(conn)

    conn = get(conn, ~p"/app/search-console/callback?#{[code: "4/kod"]}")

    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Nie udało się połączyć z Search Console"
    refute SearchConsole.get_connection(scope)
  end

  test "a state is accepted only once", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    %{conn: conn, state: state} = start_connect(conn)

    expect(Dirmoon.SearchConsoleMock, :exchange_code, 1, fn _request ->
      {:ok, %{refresh_token: "1//first", access_token: "ya29.first", email: unique_user_email()}}
    end)

    conn = get(conn, ~p"/app/search-console/callback?#{[code: "4/pierwszy", state: state]}")
    first = SearchConsole.get_connection(scope)

    conn = conn |> recycle() |> get(~p"/app/search-console/callback?#{[code: "4/drugi", state: state]}")

    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Nie udało się połączyć z Search Console"
    assert SearchConsole.refresh_token(SearchConsole.get_connection(scope)) == SearchConsole.refresh_token(first)
  end

  test "denying access at Google stores nothing and shows an error", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    %{conn: conn, state: state} = start_connect(conn)

    conn = get(conn, ~p"/app/search-console/callback?#{[error: "access_denied", state: state]}")

    assert redirected_to(conn) == ~p"/app"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Nie udało się połączyć z Search Console"
    refute SearchConsole.get_connection(scope)
  end

  test "a failed code exchange stores nothing and shows an error", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    %{conn: conn, state: state} = start_connect(conn)

    expect(Dirmoon.SearchConsoleMock, :exchange_code, 1, fn _request -> {:error, :invalid_grant} end)

    conn = get(conn, ~p"/app/search-console/callback?#{[code: "4/kod", state: state]}")

    assert redirected_to(conn) == ~p"/app"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Nie udało się połączyć z Search Console"
    refute SearchConsole.get_connection(scope)
  end

  test "connecting never touches another account's connection", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    other = insert(:search_console_connection)
    %{conn: conn, state: state} = start_connect(conn)
    stub_exchange(unique_user_email())

    get(conn, ~p"/app/search-console/callback?#{[code: "4/kod", state: state]}")

    assert SearchConsole.get_connection(scope).id != other.id
    assert Repo.get!(Connection, other.id).encrypted_refresh_token == other.encrypted_refresh_token
  end

  test "a signed-out visitor is sent to sign in and nothing is stored", %{conn: conn} do
    conn = get(conn, ~p"/app/search-console/callback?#{[code: "4/kod", state: "stan"]}")

    assert redirected_to(conn) == ~p"/users/log-in"
  end

  defp start_connect(conn, params \\ %{}) do
    stub(Dirmoon.SearchConsoleMock, :authorize_url, fn %{state: state} ->
      {:ok, "https://accounts.google.com/o/oauth2/v2/auth?" <> URI.encode_query(state: state)}
    end)

    conn = get(conn, ~p"/app/search-console/connect?#{params}")
    %{"state" => state} = conn |> redirected_to(302) |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    %{conn: recycle(conn), state: state}
  end

  defp stub_exchange(email) do
    stub(Dirmoon.SearchConsoleMock, :exchange_code, fn _request ->
      {:ok, %{refresh_token: "1//refresh-plaintext", access_token: "ya29.access-plaintext", email: email}}
    end)
  end
end
