defmodule Dirmoon.SearchConsole.Client.NotConfiguredTest do
  use ExUnit.Case, async: true

  alias Dirmoon.SearchConsole.Client.NotConfigured

  test "every call fails because Search Console is not configured" do
    not_configured = {:error, :search_console_not_configured}

    assert NotConfigured.authorize_url(%{state: "stan", redirect_uri: "http://localhost/callback"}) == not_configured
    assert NotConfigured.exchange_code(%{code: "kod", redirect_uri: "http://localhost/callback"}) == not_configured
    assert NotConfigured.refresh_access_token(%{refresh_token: "token"}) == not_configured

    assert NotConfigured.query(%{
             access_token: "token",
             site_url: "sc-domain:example.pl",
             start_date: ~D[2026-08-24],
             end_date: ~D[2026-11-21],
             row_limit: 25_000
           }) == not_configured
  end
end
