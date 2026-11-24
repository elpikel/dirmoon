defmodule Dirmoon.SearchConsole.Client.DemoTest do
  use ExUnit.Case, async: true

  alias Dirmoon.SearchConsole.Client.Demo

  @redirect_uri "http://localhost:4000/app/search-console/callback"

  test "the authorization url leads straight back to our callback with a demo code and the same state" do
    assert {:ok, url} = Demo.authorize_url(%{state: "losowy-stan", redirect_uri: @redirect_uri})

    uri = URI.parse(url)
    assert "#{uri.scheme}://#{uri.host}:#{uri.port}#{uri.path}" == @redirect_uri
    assert URI.decode_query(uri.query) == %{"code" => "demo", "state" => "losowy-stan"}
  end

  test "exchanging a code gives a fake refresh token and the demo email" do
    assert {:ok, %{refresh_token: refresh_token, access_token: access_token, email: "demo@example.com"}} =
             Demo.exchange_code(%{code: "demo", redirect_uri: @redirect_uri})

    assert refresh_token =~ "demo"
    assert access_token =~ "demo"
  end

  test "refreshing gives a fake access token" do
    assert {:ok, %{access_token: access_token, expires_in: 3600}} = Demo.refresh_access_token(%{refresh_token: "x"})
    assert access_token =~ "demo"
  end

  test "a query returns forty synthetic rows with positions spread from 1 to 40, the same every time" do
    request = %{
      access_token: "demo",
      site_url: "sc-domain:example.pl",
      start_date: ~D[2026-08-24],
      end_date: ~D[2026-11-21],
      row_limit: 25_000
    }

    assert {:ok, %{rows: rows, raw: %{"demo" => true}}} = Demo.query(request)
    assert Demo.query(request) == {:ok, %{rows: rows, raw: %{"demo" => true}}}

    assert rows |> Enum.map(&trunc(&1.position)) |> Enum.sort() == Enum.to_list(1..40)
    assert Enum.all?(rows, &String.starts_with?(&1.query, "demo fraza "))
    assert Enum.all?(rows, &(&1.clicks <= &1.impressions and &1.ctr >= 0 and &1.ctr <= 1))
  end
end
