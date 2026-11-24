defmodule Dirmoon.Hosting.DemoTest do
  use ExUnit.Case, async: true

  alias Dirmoon.Hosting.Demo

  test "a demo site is named after the site name" do
    assert Demo.create_site(%{site_name: "dirmoon-hotel-dla-psa"}) ==
             {:ok, %{site_id: "demo-site-dirmoon-hotel-dla-psa"}}
  end

  test "a demo deploy answers the same .example url for the same site every time" do
    request = %{site_id: "demo-site-dirmoon-hotel-dla-psa", html: "<html></html>"}

    assert Demo.deploy(request) == {:ok, %{url: "https://demo-dirmoon-hotel-dla-psa.example"}}
    assert Demo.deploy(request) == Demo.deploy(request)
  end
end
