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

  test "ranked phrases and the indexed page count go to the configured adapter" do
    ranked_request = %{domain: "hotel-dla-psow-testowy.example", location_code: 2616, language_code: "pl", limit: 100}
    indexed_request = %{domain: "hotel-dla-psow-testowy.example", location_code: 2616, language_code: "pl"}
    row = %{phrase: "hotel dla psów", position: 4, url: "https://hotel-dla-psow-testowy.example/", search_volume: 90}

    expect(Dirmoon.DataForSEOMock, :ranked_phrases, 1, fn ^ranked_request ->
      {:ok, %{rows: [row], raw: %{"tasks" => []}, cost: Decimal.new("0.0132")}}
    end)

    expect(Dirmoon.DataForSEOMock, :indexed_page_count, 1, fn ^indexed_request ->
      {:ok, %{count: 31, raw: %{"tasks" => []}, cost: Decimal.new("0.01")}}
    end)

    assert {:ok, %{rows: [^row]}} = DataForSEO.ranked_phrases(ranked_request)
    assert {:ok, %{count: 31}} = DataForSEO.indexed_page_count(indexed_request)
  end

  test "a Business Profile lookup goes to the configured adapter" do
    request = %{name: "Hotel dla psów Testowy", location_code: 2616, language_code: "pl"}

    expect(Dirmoon.DataForSEOMock, :business_profile, 1, fn ^request ->
      {:ok, %{profile: nil, raw: %{"tasks" => []}, cost: Decimal.new("0.0054")}}
    end)

    assert {:ok, %{profile: nil}} = DataForSEO.business_profile(request)
  end

  test "a linking sites lookup goes to the configured adapter" do
    request = %{domains: ["hotel-dla-psow-testowy.example"]}
    row = %{domain: "hotel-dla-psow-testowy.example", linking_sites: 3}

    expect(Dirmoon.DataForSEOMock, :linking_sites, 1, fn ^request ->
      {:ok, %{rows: [row], raw: %{"tasks" => []}, cost: Decimal.new("0.024036")}}
    end)

    assert {:ok, %{rows: [^row]}} = DataForSEO.linking_sites(request)
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
