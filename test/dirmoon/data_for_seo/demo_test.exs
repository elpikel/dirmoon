defmodule Dirmoon.DataForSEO.DemoTest do
  use ExUnit.Case, async: true

  alias Dirmoon.DataForSEO.Demo

  test "phrase ideas return the seed and fifteen demo phrases per seed with volume, cpc and twelve months, at no cost" do
    request = %{seeds: ["hotel dla psów", "opieka nad psem"], location_code: 2616, language_code: "pl"}

    assert {:ok, %{rows: rows, raw: %{"demo" => true}, cost: cost}} = Demo.phrase_ideas(request)

    phrases = Enum.map(rows, & &1.phrase)
    assert Enum.count(rows) == 32
    assert phrases == Enum.uniq(phrases)
    assert "hotel dla psów" in phrases
    assert "hotel dla psów demo 1" in phrases
    assert "opieka nad psem demo 15" in phrases
    assert Enum.all?(rows, &(is_integer(&1.search_volume) and &1.search_volume > 0))
    assert Enum.all?(rows, &(%Decimal{} = &1.cpc))
    assert Enum.all?(rows, &(&1.currency == "USD"))
    assert Enum.all?(rows, &(Enum.count(&1.trend) == 12))
    assert Decimal.equal?(cost, 0)
    assert Demo.phrase_ideas(request) == {:ok, %{rows: rows, raw: %{"demo" => true}, cost: cost}}
  end

  test "phrase ideas for more than twenty seeds fail like the real API" do
    seeds = Enum.map(1..21, &"fraza #{&1}")

    assert Demo.phrase_ideas(%{seeds: seeds, location_code: 2616, language_code: "pl"}) ==
             {:error, :too_many_phrases}
  end

  test "search volumes return a row for each phrase asked, smaller for the demo city than for the country" do
    phrases = ["hotel dla psów", "hotel dla psów gdańsk", "opieka nad psem"]
    {:ok, %{location_code: city_location_code}} = Demo.find_location(%{city: "Gdańsk", country_code: "PL"})

    assert {:ok, %{rows: country_rows, raw: %{"demo" => true}, cost: cost}} =
             Demo.search_volumes(%{phrases: phrases, location_code: 2616, language_code: "pl"})

    assert {:ok, %{rows: city_rows}} =
             Demo.search_volumes(%{phrases: phrases, location_code: city_location_code, language_code: "pl"})

    assert Enum.map(country_rows, & &1.phrase) == phrases
    assert Enum.map(city_rows, & &1.phrase) == phrases

    country_rows
    |> Enum.zip(city_rows)
    |> Enum.each(fn {country_row, city_row} -> assert city_row.search_volume < country_row.search_volume end)

    assert Decimal.equal?(cost, 0)
  end

  test "search volumes match the volumes phrase ideas gave for the same phrase and location" do
    {:ok, %{rows: [seed_row | _rows]}} =
      Demo.phrase_ideas(%{seeds: ["hotel dla psów"], location_code: 2616, language_code: "pl"})

    assert {:ok, %{rows: [volume_row]}} =
             Demo.search_volumes(%{phrases: ["hotel dla psów"], location_code: 2616, language_code: "pl"})

    assert volume_row == seed_row
  end

  test "search volumes for more than a thousand phrases fail like the real API" do
    phrases = Enum.map(1..1001, &"fraza #{&1}")

    assert Demo.search_volumes(%{phrases: phrases, location_code: 2616, language_code: "pl"}) ==
             {:error, :too_many_phrases}
  end

  test "the serp top 10 returns ten results on obviously fake demo domains" do
    assert {:ok, %{rows: rows, raw: %{"demo" => true}, cost: cost}} =
             Demo.serp_top10(%{phrase: "hotel dla psów", location_code: 2616, language_code: "pl"})

    assert Enum.map(rows, & &1.position) == Enum.to_list(1..10)
    assert Enum.all?(rows, &(String.starts_with?(&1.domain, "demo-") and String.ends_with?(&1.domain, ".example")))
    assert Enum.all?(rows, &String.starts_with?(&1.url, "https://" <> &1.domain <> "/"))
    assert Enum.all?(rows, &(&1.title =~ "hotel dla psów"))
    assert Decimal.equal?(cost, 0)
  end

  test "any city resolves to the demo location" do
    assert {:ok, %{location_code: location_code, name: name, raw: %{"demo" => true}, cost: cost}} =
             Demo.find_location(%{city: "Gdańsk", country_code: "PL"})

    assert is_integer(location_code)
    assert name =~ "Gdańsk"
    assert Decimal.equal?(cost, 0)
    assert {:ok, %{location_code: ^location_code}} = Demo.find_location(%{city: "Kraków", country_code: "PL"})
  end

  test "the demo countries are the United States, the United Kingdom and Poland with their real location codes" do
    assert Demo.countries() ==
             {:ok,
              [
                %{country_code: "US", location_code: 2840, name: "United States"},
                %{country_code: "GB", location_code: 2826, name: "United Kingdom"},
                %{country_code: "PL", location_code: 2616, name: "Poland"}
              ]}
  end

  test "the demo languages are English and Polish" do
    assert Demo.languages() == {:ok, [%{language_code: "en", name: "English"}, %{language_code: "pl", name: "Polish"}]}
  end

  test "ranked phrases have no demo answer, so no position or absence of one is ever invented for a real domain" do
    assert Demo.ranked_phrases(%{
             domain: "hotel-dla-psow-testowy.example",
             location_code: 2616,
             language_code: "pl",
             limit: 100
           }) == {:error, :not_in_demo_data}
  end

  test "the indexed page count has no demo answer, so no count is ever invented for a real domain" do
    assert Demo.indexed_page_count(%{domain: "hotel-dla-psow-testowy.example", location_code: 2616, language_code: "pl"}) ==
             {:error, :not_in_demo_data}
  end

  test "a business has no demo Business Profile, so none is ever invented for a real business" do
    assert Demo.business_profile(%{name: "Hotel dla psów Testowy", location_code: 2616, language_code: "pl"}) ==
             {:error, :not_in_demo_data}
  end

  test "no domain has demo linking sites, so no number of sites linking to a real site is ever invented" do
    assert Demo.linking_sites(%{domains: ["hotel-dla-psow-testowy.example"]}) == {:error, :not_in_demo_data}
  end
end
