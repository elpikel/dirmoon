defmodule Dirmoon.DataForSEO.NotConfiguredTest do
  use ExUnit.Case, async: true

  alias Dirmoon.DataForSEO.NotConfigured

  test "every request fails because DataForSEO is not configured" do
    not_configured = {:error, :data_for_seo_not_configured}

    assert NotConfigured.phrase_ideas(%{seeds: ["hotel dla psów"], location_code: 2616, language_code: "pl"}) ==
             not_configured

    assert NotConfigured.search_volumes(%{phrases: ["hotel dla psów"], location_code: 2616, language_code: "pl"}) ==
             not_configured

    assert NotConfigured.serp_top10(%{phrase: "hotel dla psów", location_code: 2616, language_code: "pl"}) ==
             not_configured

    assert NotConfigured.find_location(%{city: "Gdańsk", country_code: "PL"}) == not_configured
    assert NotConfigured.countries() == not_configured
    assert NotConfigured.languages() == not_configured
  end
end
