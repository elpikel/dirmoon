defmodule Dirmoon.Hosting.NotConfiguredTest do
  use ExUnit.Case, async: true

  alias Dirmoon.Hosting.NotConfigured

  test "creating a site fails as hosting not configured" do
    assert NotConfigured.create_site(%{site_name: "dirmoon-strona"}) == {:error, :hosting_not_configured}
  end

  test "every deploy fails as hosting not configured" do
    assert NotConfigured.deploy(%{site_id: "site", html: "<html></html>"}) == {:error, :hosting_not_configured}
  end
end
