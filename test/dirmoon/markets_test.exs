defmodule Dirmoon.MarketsTest do
  use Dirmoon.DataCase, async: true

  import Mox

  alias Dirmoon.Markets
  alias Dirmoon.Markets.Country
  alias Dirmoon.Markets.Language

  test "stored countries younger than the maximum age are listed by name without asking the keyword API" do
    insert(:market_country, name: "Zambia")
    insert(:market_country, name: "Albania")

    assert {:ok, [%Country{name: "Albania"}, %Country{name: "Zambia"}]} = Markets.countries()
  end

  test "with no countries stored, the keyword API's countries are stored and listed by name" do
    expect(Dirmoon.DataForSEOMock, :countries, 1, fn ->
      {:ok,
       [
         %{country_code: "US", location_code: 2840, name: "United States"},
         %{country_code: "BR", location_code: 2076, name: "Brazil"}
       ]}
    end)

    assert {:ok, [%Country{country_code: "BR", location_code: 2076}, %Country{country_code: "US"}]} =
             Markets.countries()

    assert {:ok, [%Country{name: "Brazil"}, %Country{name: "United States"}]} = Markets.countries()
    assert Repo.get_by!(Country, country_code: "US").fetched_at
  end

  test "countries older than the maximum age are fetched again, and a country no longer listed is dropped" do
    stale_at = DateTime.shift(DateTime.utc_now(:second), day: -(max_age_days() + 1))
    insert(:market_country, country_code: "US", location_code: 2840, name: "United States", fetched_at: stale_at)
    dropped = insert(:market_country, fetched_at: stale_at)

    expect(Dirmoon.DataForSEOMock, :countries, 1, fn ->
      {:ok, [%{country_code: "US", location_code: 2840, name: "United States of America"}]}
    end)

    assert {:ok, [%Country{country_code: "US", name: "United States of America", fetched_at: fetched_at}]} =
             Markets.countries()

    assert DateTime.after?(fetched_at, stale_at)
    refute Repo.get_by(Country, country_code: dropped.country_code)
  end

  test "a country the keyword API lists twice is stored once" do
    expect(Dirmoon.DataForSEOMock, :countries, 1, fn ->
      {:ok,
       [
         %{country_code: "PL", location_code: 2616, name: "Poland"},
         %{country_code: "PL", location_code: 2616, name: "Poland"}
       ]}
    end)

    assert {:ok, [%Country{country_code: "PL"}]} = Markets.countries()
  end

  test "when refreshing old countries fails, the stored countries are still listed" do
    stale_at = DateTime.shift(DateTime.utc_now(:second), day: -(max_age_days() + 1))
    stored = insert(:market_country, fetched_at: stale_at)

    expect(Dirmoon.DataForSEOMock, :countries, 1, fn -> {:error, "DataForSEO: HTTP 502"} end)

    assert {:ok, [%Country{country_code: country_code}]} = Markets.countries()
    assert country_code == stored.country_code
  end

  test "when the keyword API answers old countries with an empty list, the stored countries are still listed" do
    stale_at = DateTime.shift(DateTime.utc_now(:second), day: -(max_age_days() + 1))
    stored = insert(:market_country, fetched_at: stale_at)

    expect(Dirmoon.DataForSEOMock, :countries, 1, fn -> {:ok, []} end)

    assert {:ok, [%Country{country_code: country_code}]} = Markets.countries()
    assert country_code == stored.country_code
  end

  test "with no countries stored and the keyword API failing, the countries are an error" do
    expect(Dirmoon.DataForSEOMock, :countries, 1, fn -> {:error, :data_for_seo_not_configured} end)

    assert Markets.countries() == {:error, :data_for_seo_not_configured}
  end

  test "with no countries stored and an empty answer from the keyword API, the countries are an error" do
    expect(Dirmoon.DataForSEOMock, :countries, 1, fn -> {:ok, []} end)

    assert Markets.countries() == {:error, :empty_list}
  end

  test "stored languages younger than the maximum age are listed by name without asking the keyword API" do
    insert(:market_language, name: "Swahili")
    insert(:market_language, name: "Arabic")

    assert {:ok, [%Language{name: "Arabic"}, %Language{name: "Swahili"}]} = Markets.languages()
  end

  test "with no languages stored, the keyword API's languages are stored and listed by name" do
    expect(Dirmoon.DataForSEOMock, :languages, 1, fn ->
      {:ok, [%{language_code: "pt", name: "Portuguese"}, %{language_code: "ar", name: "Arabic"}]}
    end)

    assert {:ok, [%Language{language_code: "ar"}, %Language{language_code: "pt"}]} = Markets.languages()
    assert %Language{name: "Portuguese"} = Repo.get_by!(Language, language_code: "pt")
  end

  test "with no languages stored and the keyword API failing, the languages are an error" do
    expect(Dirmoon.DataForSEOMock, :languages, 1, fn -> {:error, :data_for_seo_not_configured} end)

    assert Markets.languages() == {:error, :data_for_seo_not_configured}
  end

  test "a market is found from the stored country and language codes" do
    country = insert(:market_country)
    language = insert(:market_language)

    assert %{country: %Country{name: country_name}, language: %Language{name: language_name}} =
             Markets.find_market(%{country_code: country.country_code, language_code: language.language_code})

    assert country_name == country.name
    assert language_name == language.name
  end

  test "codes that are missing or not stored find no country and no language" do
    assert Markets.find_market(%{country_code: "T-unknown", language_code: "x-unknown"}) == %{country: nil, language: nil}
    assert Markets.find_market(%{country_code: nil, language_code: nil}) == %{country: nil, language: nil}
  end

  test "a first run starts in the United States, in English" do
    assert Markets.default_market() == %{country_code: "US", language_code: "en"}
  end

  defp max_age_days, do: Application.fetch_env!(:dirmoon, :market_lists_max_age_days)
end
