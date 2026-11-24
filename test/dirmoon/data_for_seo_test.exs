defmodule Dirmoon.DataForSEOTest do
  use ExUnit.Case, async: false

  import Mox

  alias Dirmoon.DataForSEO

  test "a request goes to the configured adapter and returns its rows, raw response and cost" do
    request = %{phrase: "hotel dla psów", location_code: 2616, language_code: "pl"}
    row = %{position: 1, url: "https://demo-blog-1.example/hotel", domain: "demo-blog-1.example", title: "Hotel"}

    expect(Dirmoon.DataForSEOMock, :serp_top10, 1, fn ^request ->
      {:ok, %{rows: [row], raw: %{"tasks" => []}, cost: Decimal.new("0.002")}}
    end)

    assert {:ok, %{rows: [^row], raw: %{"tasks" => []}, cost: cost}} = DataForSEO.serp_top10(request)
    assert Decimal.equal?(cost, Decimal.new("0.002"))
  end

  test "without credentials production uses the not-configured adapter and dev uses demo data" do
    production = Config.Reader.read!("config/config.exs", env: :prod)
    dev = Config.Reader.read!("config/config.exs", env: :dev)

    assert get_in(production, [:dirmoon, :data_for_seo_adapter]) == DataForSEO.NotConfigured
    assert get_in(dev, [:dirmoon, :data_for_seo_adapter]) == DataForSEO.Demo
  end

  test "credentials in env vars switch to the HTTP adapter with those credentials" do
    previous_env = Map.new(["DATAFORSEO_LOGIN", "DATAFORSEO_PASSWORD"], &{&1, System.get_env(&1)})
    System.put_env("DATAFORSEO_LOGIN", "env-login")
    System.put_env("DATAFORSEO_PASSWORD", "env-password")

    config =
      try do
        Config.Reader.read!("config/runtime.exs", env: :dev)
      after
        Enum.each(previous_env, &restore_env/1)
      end

    assert get_in(config, [:dirmoon, :data_for_seo_adapter]) == DataForSEO.HTTP
    assert get_in(config, [:dirmoon, DataForSEO.HTTP, :login]) == "env-login"
    assert get_in(config, [:dirmoon, DataForSEO.HTTP, :password]) == "env-password"
  end

  defp restore_env({name, nil}), do: System.delete_env(name)
  defp restore_env({name, value}), do: System.put_env(name, value)
end
