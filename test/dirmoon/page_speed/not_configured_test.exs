defmodule Dirmoon.PageSpeed.NotConfiguredTest do
  use ExUnit.Case, async: true

  alias Dirmoon.PageSpeed.NotConfigured

  test "every check fails because PageSpeed is not configured" do
    assert NotConfigured.check(%{url: "https://hotel-dla-psow-testowy.example/"}) ==
             {:error, :page_speed_not_configured}
  end
end
