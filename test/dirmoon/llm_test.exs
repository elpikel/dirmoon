defmodule Dirmoon.LLMTest do
  use ExUnit.Case, async: true

  import Mox

  alias Dirmoon.LLM

  test "a structured request goes to the configured adapter and returns its map and cost" do
    request = seeds_request()

    expect(Dirmoon.LLMMock, :structured, 1, fn ^request ->
      {:ok, %{"seeds" => ["hotel dla psów"], "questions" => ["Ile to kosztuje?"]}, Decimal.new("0.002")}
    end)

    assert {:ok, %{"seeds" => ["hotel dla psów"]}, cost} = LLM.structured(request)
    assert Decimal.equal?(cost, Decimal.new("0.002"))
  end

  test "a structured request returns the adapter's error" do
    expect(Dirmoon.LLMMock, :structured, 1, fn _request -> {:error, :timeout} end)

    assert {:error, :timeout} = LLM.structured(seeds_request())
  end

  test "the known tasks are seeds, filter and group, label serp, brief, competitor prices, page matching and site description" do
    assert LLM.tasks() == [
             :seeds,
             :filter_and_group,
             :label_serp,
             :brief,
             :competitor_prices,
             :match_pages,
             :describe_site
           ]
  end

  test "without a provider the production config uses the not-configured adapter" do
    config = Config.Reader.read!("config/config.exs", env: :prod)

    assert get_in(config, [:dirmoon, :llm_adapter]) == Dirmoon.LLM.NotConfigured
  end

  test "dev answers with the demo adapter" do
    config = Config.Reader.read!("config/config.exs", env: :dev)

    assert get_in(config, [:dirmoon, :llm_adapter]) == Dirmoon.LLM.Demo
  end

  defp seeds_request do
    %{
      task: :seeds,
      system: "Jesteś ekspertem SEO.",
      prompt: "Wymyśl frazy dla hotelu dla psów.",
      schema: %{"type" => "object"},
      input: %{description: "Hotel dla psów", city: nil, priority_services: []}
    }
  end
end
