defmodule DirmoonWeb.Controllers.SearchConsole.ConnectTest do
  use DirmoonWeb.ConnCase, async: true

  import Mox

  test "connecting sends the user to Google's consent screen with a fresh state and our callback", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    callback_url = url(~p"/app/search-console/callback")

    expect(Dirmoon.SearchConsoleMock, :authorize_url, 1, fn %{state: state, redirect_uri: ^callback_url} ->
      {:ok, "https://accounts.google.com/o/oauth2/v2/auth?" <> URI.encode_query(state: state)}
    end)

    conn = get(conn, ~p"/app/search-console/connect")

    location = redirected_to(conn, 302)
    assert String.starts_with?(location, "https://accounts.google.com/o/oauth2/v2/auth?")
    %{"state" => state} = location |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert byte_size(state) >= 32
  end

  test "each connect attempt gets a different state", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    stub_authorize_url()

    first = conn |> get(~p"/app/search-console/connect") |> redirected_to(302)
    second = conn |> get(~p"/app/search-console/connect") |> redirected_to(302)

    assert first != second
  end

  test "when Search Console is not configured the user stays in the app and sees why", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})

    expect(Dirmoon.SearchConsoleMock, :authorize_url, 1, fn _request -> {:error, :search_console_not_configured} end)

    conn = get(conn, ~p"/app/search-console/connect")

    assert redirected_to(conn) == ~p"/app"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Search Console nie jest skonfigurowane"
  end

  test "when Search Console is not configured the user goes back to the app page they came from", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})

    expect(Dirmoon.SearchConsoleMock, :authorize_url, 1, fn _request -> {:error, :search_console_not_configured} end)

    conn = get(conn, ~p"/app/search-console/connect?return_to=/app/runs/12")

    assert redirected_to(conn) == "/app/runs/12"
  end

  test "an external return address is ignored", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})

    stub(Dirmoon.SearchConsoleMock, :authorize_url, fn _request -> {:error, :search_console_not_configured} end)

    for return_to <- [
          "https://evil.example/app",
          "//evil.example/app",
          "/users/settings",
          "/app.evil",
          "/app\\evil",
          "/app\n/x",
          "/app/\t/evil.example",
          "/app\r\nSet-Cookie: x"
        ] do
      conn = get(conn, ~p"/app/search-console/connect?#{[return_to: return_to]}")
      assert redirected_to(conn) == ~p"/app"
    end
  end

  test "a signed-out visitor is sent to sign in", %{conn: conn} do
    conn = get(conn, ~p"/app/search-console/connect")

    assert redirected_to(conn) == ~p"/users/log-in"
  end

  defp stub_authorize_url do
    stub(Dirmoon.SearchConsoleMock, :authorize_url, fn %{state: state} ->
      {:ok, "https://accounts.google.com/o/oauth2/v2/auth?" <> URI.encode_query(state: state)}
    end)
  end
end
