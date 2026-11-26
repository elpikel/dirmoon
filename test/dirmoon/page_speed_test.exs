defmodule Dirmoon.PageSpeedTest do
  use ExUnit.Case, async: false

  import Mox

  alias Dirmoon.PageSpeed

  test "a check goes to the configured adapter and returns its result and raw answer" do
    request = %{url: "https://hotel-dla-psow-testowy.example/"}

    expect(Dirmoon.PageSpeedMock, :check, 1, fn ^request ->
      {:ok, %{result: %{"performance_score" => 64}, raw: %{"kind" => "pagespeedonline#result"}}}
    end)

    assert {:ok, %{result: %{"performance_score" => 64}}} = PageSpeed.check(request)
  end

  test "without a key every environment uses the not-configured adapter" do
    for env <- [:prod, :dev] do
      config = Config.Reader.read!("config/config.exs", env: env)

      assert get_in(config, [:dirmoon, :page_speed_adapter]) == PageSpeed.NotConfigured
    end
  end

  test "a key in the env var switches to the HTTP adapter with that key, and a blank one does not" do
    with_env("env-pagespeed-key", fn config ->
      assert get_in(config, [:dirmoon, :page_speed_adapter]) == PageSpeed.HTTP
      assert get_in(config, [:dirmoon, PageSpeed.HTTP, :api_key]) == "env-pagespeed-key"
    end)

    with_env("", fn config ->
      assert get_in(config, [:dirmoon, :page_speed_adapter]) == nil
    end)
  end

  defp with_env(value, check) do
    previous = System.get_env("PAGESPEED_API_KEY")
    System.put_env("PAGESPEED_API_KEY", value)

    config =
      try do
        Config.Reader.read!("config/runtime.exs", env: :dev)
      after
        if previous, do: System.put_env("PAGESPEED_API_KEY", previous), else: System.delete_env("PAGESPEED_API_KEY")
      end

    check.(config)
  end
end
