defmodule Dirmoon.SearchConsole.PositionsTest do
  use Dirmoon.DataCase, async: true

  import Mox

  alias Dirmoon.Accounts
  alias Dirmoon.SearchConsole
  alias Dirmoon.SearchConsole.Positions

  @refresh_token "1//refresh-token-plaintext"
  @access_token "ya29.access-token-plaintext"

  test "a connection that can read the domain answers its queries of the last 90 days" do
    run = existing_site_run()
    connect(run)
    today = Date.utc_today()
    expected_start = Date.add(today, -90)
    expected_end = Date.add(today, -1)
    site_url = "sc-domain:" <> run.domain

    expect(Dirmoon.SearchConsoleMock, :query, 1, fn request ->
      assert %{site_url: ^site_url, start_date: ^expected_start, end_date: ^expected_end, row_limit: 5000} = request
      assert request.access_token == @access_token
      rows([row("adwokat rozwód", 12.3)])
    end)

    assert Positions.rows(run) ==
             {:ok,
              %{
                rows: [row("adwokat rozwód", 12.3)],
                window: %{start_date: expected_start, end_date: expected_end}
              }}
  end

  test "the queries are capped at 5000 rows" do
    run = existing_site_run()
    connect(run)
    returned_rows = Enum.map(1..5001, &row("zapytanie #{&1}", 30.0))

    stub_query(fn _request -> rows(returned_rows) end)

    assert {:ok, %{rows: kept_rows}} = Positions.rows(run)
    assert Enum.count(kept_rows) == 5000
    refute Enum.any?(kept_rows, &(&1.query == "zapytanie 5001"))
  end

  test "an account without a connection makes Search Console unavailable" do
    run = existing_site_run()

    assert Positions.rows(run) == {:unavailable, "Search Console is not connected"}
  end

  test "another account's connection is never used for the run" do
    run = existing_site_run()
    connect(existing_site_run())

    assert Positions.rows(run) == {:unavailable, "Search Console is not connected"}
  end

  test "a property the Google user can't access makes Search Console unavailable naming the domain" do
    run = existing_site_run()
    connect(run)

    stub_query(fn _request -> {:error, :forbidden} end)

    assert Positions.rows(run) == {:unavailable, "No access to #{run.domain} in Search Console"}
  end

  test "a revoked or expired connection makes Search Console unavailable until a reconnect" do
    run = existing_site_run()
    connect(run)

    stub(Dirmoon.SearchConsoleMock, :refresh_access_token, fn _request -> {:error, :invalid_grant} end)

    assert Positions.rows(run) == {:unavailable, "The Search Console connection expired, connect again"}
  end

  test "a refresh token that no longer decrypts makes Search Console unavailable until a reconnect" do
    run = existing_site_run()
    insert(:search_console_connection, account: run.account)

    assert Positions.rows(run) == {:unavailable, "The Search Console connection expired, connect again"}
  end

  test "Search Console without credentials is unavailable when refreshing the token" do
    run = existing_site_run()
    connect(run)

    stub(Dirmoon.SearchConsoleMock, :refresh_access_token, fn _request -> {:error, :search_console_not_configured} end)

    assert Positions.rows(run) == {:unavailable, "Search Console is not configured"}
  end

  test "Search Console without credentials is unavailable when querying" do
    run = existing_site_run()
    connect(run)

    stub_query(fn _request -> {:error, :search_console_not_configured} end)

    assert Positions.rows(run) == {:unavailable, "Search Console is not configured"}
  end

  test "a rejected access token is an error to retry with a fresh token" do
    run = existing_site_run()
    connect(run)

    stub_query(fn _request -> {:error, :unauthorized} end)

    assert Positions.rows(run) == {:error, "Search Console rejected the access token"}
  end

  test "a failed token refresh other than an invalid grant is an error to retry" do
    run = existing_site_run()
    connect(run)

    stub(Dirmoon.SearchConsoleMock, :refresh_access_token, fn _request -> {:error, "Google OAuth: HTTP 503"} end)

    assert Positions.rows(run) == {:error, "Google OAuth: HTTP 503"}
  end

  test "a failed query other than forbidden or unauthorized is an error to retry" do
    run = existing_site_run()
    connect(run)

    stub_query(fn _request -> {:error, "Google Search Console: HTTP 500"} end)

    assert Positions.rows(run) == {:error, "Google Search Console: HTTP 500"}
  end

  defp existing_site_run do
    insert(:run, mode: :existing_site, domain: "kancelaria-testowa.pl")
  end

  defp connect(run) do
    scope =
      :membership
      |> insert(account: run.account)
      |> Map.fetch!(:user)
      |> Accounts.scope_for_user()

    stub(Dirmoon.SearchConsoleMock, :exchange_code, fn _request ->
      {:ok, %{refresh_token: @refresh_token, access_token: @access_token, email: unique_user_email()}}
    end)

    stub(Dirmoon.SearchConsoleMock, :refresh_access_token, fn %{refresh_token: @refresh_token} ->
      {:ok, %{access_token: @access_token, expires_in: 3599}}
    end)

    {:ok, _connection} = SearchConsole.connect(scope, %{code: "kod", redirect_uri: "http://localhost/callback"})
  end

  defp stub_query(fun), do: stub(Dirmoon.SearchConsoleMock, :query, fun)

  defp row(query, position), do: %{query: query, clicks: 3, impressions: 120, ctr: 0.025, position: position}

  defp rows(rows), do: {:ok, %{rows: rows, raw: %{"rows" => []}}}
end
