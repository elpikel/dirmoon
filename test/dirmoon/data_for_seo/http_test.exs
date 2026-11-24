defmodule Dirmoon.DataForSEO.HTTPTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Dirmoon.DataForSEO.HTTP

  @login "test-dataforseo-login"
  @password "test-dataforseo-password"

  test "keyword ideas return the phrases with volume, cpc in USD, monthly trend, the raw response and the cost" do
    stub_json(keywords_for_keywords_body())

    assert {:ok, %{rows: rows, raw: raw, cost: cost}} =
             HTTP.keyword_ideas(%{seeds: ["buty do biegania"], location_code: 2616, language_code: "pl"})

    assert [first, second] = rows
    assert first.phrase == "buty do biegania"
    assert first.search_volume == 27_100
    assert Decimal.equal?(first.cpc, Decimal.new("0.38"))
    assert first.currency == "USD"

    assert first.monthly_searches == [
             %{year: 2026, month: 10, search_volume: 22_200},
             %{year: 2026, month: 9, search_volume: 27_100}
           ]

    assert second == %{
             phrase: "buty do biegania damskie",
             search_volume: nil,
             cpc: nil,
             currency: "USD",
             monthly_searches: []
           }

    assert raw == keywords_for_keywords_body()
    assert Decimal.equal?(cost, Decimal.new("0.09"))
  end

  test "keyword ideas post one task with the seeds, location and language to the keywords for keywords endpoint" do
    stub_json(keywords_for_keywords_body())

    HTTP.keyword_ideas(%{seeds: ["buty do biegania", "buty trailowe"], location_code: 2616, language_code: "pl"})

    assert_received {:request, %{method: "POST", path: path, body: body}}
    assert path == "/v3/keywords_data/google_ads/keywords_for_keywords/live"

    assert Jason.decode!(body) == [
             %{"keywords" => ["buty do biegania", "buty trailowe"], "location_code" => 2616, "language_code" => "pl"}
           ]
  end

  test "keyword ideas for more than twenty seeds fail without a request" do
    stub_json(keywords_for_keywords_body())
    seeds = Enum.map(1..21, &"fraza #{&1}")

    assert HTTP.keyword_ideas(%{seeds: seeds, location_code: 2616, language_code: "pl"}) ==
             {:error, :too_many_keywords}

    refute_received {:request, _request}
  end

  test "search volumes return volume, cpc and trend per phrase, the raw response and the cost" do
    stub_json(search_volume_body())

    assert {:ok, %{rows: rows, raw: raw, cost: cost}} =
             HTTP.search_volumes(%{phrases: ["kup laptop", "tani laptop"], location_code: 2616, language_code: "pl"})

    assert [kup, tani] = rows
    assert kup.phrase == "kup laptop"
    assert kup.search_volume == 2900
    assert Decimal.equal?(kup.cpc, Decimal.new("7.95"))
    assert kup.currency == "USD"

    assert kup.monthly_searches == [
             %{year: 2026, month: 10, search_volume: 2400},
             %{year: 2026, month: 9, search_volume: 2900}
           ]

    assert tani.phrase == "tani laptop"
    assert tani.search_volume == 1300
    assert raw == search_volume_body()
    assert Decimal.equal?(cost, Decimal.new("0.09"))
  end

  test "search volumes post one task with the phrases to the search volume endpoint" do
    stub_json(search_volume_body())

    HTTP.search_volumes(%{phrases: ["kup laptop", "tani laptop"], location_code: 1_011_615, language_code: "pl"})

    assert_received {:request, %{method: "POST", path: path, body: body}}
    assert path == "/v3/keywords_data/google_ads/search_volume/live"

    assert Jason.decode!(body) == [
             %{"keywords" => ["kup laptop", "tani laptop"], "location_code" => 1_011_615, "language_code" => "pl"}
           ]
  end

  test "search volumes for more than a thousand phrases fail without a request" do
    stub_json(search_volume_body())
    phrases = Enum.map(1..1001, &"fraza #{&1}")

    assert HTTP.search_volumes(%{phrases: phrases, location_code: 2616, language_code: "pl"}) ==
             {:error, :too_many_keywords}

    refute_received {:request, _request}
  end

  test "the serp top 10 returns only organic results with position, url, domain and title, the raw response and the cost" do
    stub_json(serp_body())

    assert {:ok, %{rows: rows, raw: raw, cost: cost}} =
             HTTP.serp_top10(%{phrase: "buty do biegania", location_code: 2616, language_code: "pl"})

    assert rows == [
             %{
               position: 1,
               url: "https://www.example.pl/buty-do-biegania",
               domain: "www.example.pl",
               title: "Buty do biegania – sklep"
             },
             %{
               position: 2,
               url: "https://dirmoon-test.netlify.app/buty",
               domain: "dirmoon-test.netlify.app",
               title: "Ranking butów"
             }
           ]

    assert raw == serp_body()
    assert Decimal.equal?(cost, Decimal.new("0.002"))
  end

  test "the serp top 10 posts one task with depth 10 to the organic live advanced endpoint" do
    stub_json(serp_body())

    HTTP.serp_top10(%{phrase: "buty do biegania", location_code: 2616, language_code: "pl"})

    assert_received {:request, %{method: "POST", path: path, body: body}}
    assert path == "/v3/serp/google/organic/live/advanced"

    assert Jason.decode!(body) == [
             %{"keyword" => "buty do biegania", "location_code" => 2616, "language_code" => "pl", "depth" => 10}
           ]
  end

  test "the serp top 10 keeps at most ten organic results ordered by position" do
    items = Enum.map(12..1//-1, &organic_item/1)
    stub_json(serp_body_with_items(items))

    assert {:ok, %{rows: rows}} = HTTP.serp_top10(%{phrase: "hotel dla psów", location_code: 2616, language_code: "pl"})

    assert Enum.map(rows, & &1.position) == Enum.to_list(1..10)
  end

  test "the serp top 10 with no search results returns no rows" do
    stub_json(failed_task_body(%{status_code: 40_102, status_message: "No Search Results."}))

    assert {:ok, %{rows: [], cost: cost}} =
             HTTP.serp_top10(%{phrase: "fraza bez wyników", location_code: 2616, language_code: "pl"})

    assert Decimal.equal?(cost, 0)
  end

  test "a city is resolved to its location code from the country's city locations" do
    stub_json(locations_body())

    assert {:ok, %{location_code: 1_011_615, name: "Warsaw,Masovian Voivodeship,Poland", raw: raw, cost: cost}} =
             HTTP.find_location(%{city: "warsaw", country_code: "PL"})

    assert raw == locations_body()
    assert Decimal.equal?(cost, 0)
    assert_received {:request, %{method: "GET", path: "/v3/keywords_data/google_ads/locations/pl"}}
  end

  test "a city name without Polish diacritics matches the city with them" do
    stub_json(locations_body())

    assert {:ok, %{location_code: 1_011_700}} = HTTP.find_location(%{city: "Gdansk", country_code: "PL"})
    assert {:ok, %{location_code: 1_011_800}} = HTTP.find_location(%{city: " Łódź ", country_code: "PL"})
  end

  test "a city the country has no city location for is not found" do
    stub_json(locations_body())

    assert HTTP.find_location(%{city: "Mazowieckie", country_code: "PL"}) == {:error, :not_found}
    assert HTTP.find_location(%{city: "Masovian Voivodeship", country_code: "PL"}) == {:error, :not_found}
  end

  test "an error status from DataForSEO returns its message" do
    stub_json(
      %{"status_code" => 40_200, "status_message" => "Payment Required.", "cost" => 0, "tasks" => nil},
      402
    )

    assert HTTP.keyword_ideas(%{seeds: ["hotel dla psów"], location_code: 2616, language_code: "pl"}) ==
             {:error, "DataForSEO: Payment Required."}
  end

  test "an error status at the top level of a 200 response returns its message" do
    stub_json(%{"status_code" => 40_000, "status_message" => "You can set only one task at a time.", "tasks" => []})

    assert HTTP.serp_top10(%{phrase: "hotel dla psów", location_code: 2616, language_code: "pl"}) ==
             {:error, "DataForSEO: You can set only one task at a time."}
  end

  test "a failed task inside a 200 response returns the task's message" do
    stub_json(failed_task_body(%{status_code: 40_501, status_message: "Invalid Field: 'location_code'."}))

    assert HTTP.search_volumes(%{phrases: ["hotel dla psów"], location_code: 1, language_code: "pl"}) ==
             {:error, "DataForSEO: Invalid Field: 'location_code'."}
  end

  test "a failed task without a status message returns its status code" do
    stub_json(
      update_in(failed_task_body(%{status_code: 40_503, status_message: nil}), ["tasks"], &task_without_message/1)
    )

    assert HTTP.keyword_ideas(%{seeds: ["hotel dla psów"], location_code: 2616, language_code: "pl"}) ==
             {:error, "DataForSEO: status 40503"}
  end

  test "a country code that is not two ASCII letters is rejected without a request" do
    stub_json(locations_body())

    assert HTTP.find_location(%{city: "Gdańsk", country_code: "../pl"}) == {:error, :invalid_country_code}
    assert HTTP.find_location(%{city: "Gdańsk", country_code: "PLN"}) == {:error, :invalid_country_code}
    assert HTTP.find_location(%{city: "Gdańsk", country_code: "Ł1"}) == {:error, :invalid_country_code}
    refute_received {:request, _request}
  end

  test "a transport failure returns an error" do
    Req.Test.stub(HTTP, &Req.Test.transport_error(&1, :econnrefused))

    assert {:error, "DataForSEO: " <> _reason} =
             HTTP.find_location(%{city: "Gdańsk", country_code: "PL"})
  end

  test "requests use HTTP Basic auth with the configured credentials" do
    stub_json(search_volume_body())

    HTTP.search_volumes(%{phrases: ["kup laptop"], location_code: 2616, language_code: "pl"})

    assert_received {:request, %{authorization: authorization}}
    assert authorization == "Basic " <> Base.encode64("#{@login}:#{@password}")
  end

  test "the credentials never appear in a returned response, an error or a log" do
    stub_json(keywords_for_keywords_body())

    success_log =
      capture_log(fn ->
        assert {:ok, %{raw: raw}} =
                 HTTP.keyword_ideas(%{seeds: ["buty do biegania"], location_code: 2616, language_code: "pl"})

        refute inspect(raw) =~ @password
        refute inspect(raw) =~ @login
      end)

    stub_json(%{"status_code" => 40_100, "status_message" => "You are not authorized to access this resource."}, 401)

    error_log =
      capture_log(fn ->
        assert {:error, reason} = HTTP.serp_top10(%{phrase: "hotel", location_code: 2616, language_code: "pl"})
        refute inspect(reason) =~ @password
        refute inspect(reason) =~ @login
      end)

    refute success_log =~ @password
    refute error_log =~ @password
  end

  defp stub_json(body, status \\ 200) do
    test_pid = self()

    Req.Test.stub(HTTP, fn conn ->
      {:ok, request_body, conn} = Plug.Conn.read_body(conn)

      send(test_pid, {
        :request,
        %{
          method: conn.method,
          path: conn.request_path,
          body: request_body,
          authorization: conn |> Plug.Conn.get_req_header("authorization") |> List.first()
        }
      })

      conn
      |> Plug.Conn.put_status(status)
      |> Req.Test.json(body)
    end)
  end

  defp envelope(%{cost: cost, task: task}) do
    %{
      "version" => "0.1.20231117",
      "status_code" => 20_000,
      "status_message" => "Ok.",
      "time" => "1.8776 sec.",
      "cost" => cost,
      "tasks_count" => 1,
      "tasks_error" => 0,
      "tasks" => [Map.merge(%{"id" => "11302008-1535-0368-0000-000000000000", "time" => "1.8 sec."}, task)]
    }
  end

  defp keywords_for_keywords_body do
    envelope(%{
      cost: 0.09,
      task: %{
        "status_code" => 20_000,
        "status_message" => "Ok.",
        "cost" => 0.09,
        "result_count" => 2,
        "path" => ["v3", "keywords_data", "google_ads", "keywords_for_keywords", "live"],
        "data" => %{"api" => "keywords_data", "function" => "keywords_for_keywords", "se" => "google_ads"},
        "result" => [
          %{
            "keyword" => "buty do biegania",
            "location_code" => 2616,
            "language_code" => "pl",
            "search_partners" => false,
            "competition" => "HIGH",
            "competition_index" => 100,
            "search_volume" => 27_100,
            "low_top_of_page_bid" => 0.21,
            "high_top_of_page_bid" => 0.74,
            "cpc" => 0.38,
            "monthly_searches" => [
              %{"year" => 2026, "month" => 10, "search_volume" => 22_200},
              %{"year" => 2026, "month" => 9, "search_volume" => 27_100}
            ],
            "keyword_annotations" => %{"concepts" => nil}
          },
          %{
            "keyword" => "buty do biegania damskie",
            "location_code" => 2616,
            "language_code" => "pl",
            "search_partners" => false,
            "competition" => nil,
            "competition_index" => nil,
            "search_volume" => nil,
            "low_top_of_page_bid" => nil,
            "high_top_of_page_bid" => nil,
            "cpc" => nil,
            "monthly_searches" => nil,
            "keyword_annotations" => %{"concepts" => nil}
          }
        ]
      }
    })
  end

  defp search_volume_body do
    envelope(%{
      cost: 0.09,
      task: %{
        "status_code" => 20_000,
        "status_message" => "Ok.",
        "cost" => 0.09,
        "result_count" => 2,
        "path" => ["v3", "keywords_data", "google_ads", "search_volume", "live"],
        "data" => %{"api" => "keywords_data", "function" => "search_volume", "se" => "google_ads"},
        "result" => [
          %{
            "keyword" => "kup laptop",
            "spell" => nil,
            "location_code" => 2616,
            "language_code" => "pl",
            "search_partners" => false,
            "competition" => "HIGH",
            "competition_index" => 100,
            "search_volume" => 2900,
            "low_top_of_page_bid" => 1.69,
            "high_top_of_page_bid" => 10.04,
            "cpc" => 7.95,
            "monthly_searches" => [
              %{"year" => 2026, "month" => 10, "search_volume" => 2400},
              %{"year" => 2026, "month" => 9, "search_volume" => 2900}
            ]
          },
          %{
            "keyword" => "tani laptop",
            "spell" => nil,
            "location_code" => 2616,
            "language_code" => "pl",
            "search_partners" => false,
            "competition" => "MEDIUM",
            "competition_index" => 55,
            "search_volume" => 1300,
            "low_top_of_page_bid" => 0.5,
            "high_top_of_page_bid" => 2.1,
            "cpc" => 1.2,
            "monthly_searches" => [%{"year" => 2026, "month" => 10, "search_volume" => 1300}]
          }
        ]
      }
    })
  end

  defp serp_body do
    serp_body_with_items([
      %{
        "type" => "paid",
        "rank_group" => 1,
        "rank_absolute" => 1,
        "domain" => "www.ads.example",
        "title" => "Ad",
        "url" => "https://www.ads.example/"
      },
      %{
        "type" => "organic",
        "rank_group" => 1,
        "rank_absolute" => 2,
        "page" => 1,
        "position" => "left",
        "domain" => "www.example.pl",
        "title" => "Buty do biegania – sklep",
        "url" => "https://www.example.pl/buty-do-biegania",
        "description" => "Szeroki wybór butów..."
      },
      %{
        "type" => "organic",
        "rank_group" => 2,
        "rank_absolute" => 3,
        "page" => 1,
        "position" => "left",
        "domain" => "dirmoon-test.netlify.app",
        "title" => "Ranking butów",
        "url" => "https://dirmoon-test.netlify.app/buty",
        "description" => "..."
      }
    ])
  end

  defp serp_body_with_items(items) do
    envelope(%{
      cost: 0.002,
      task: %{
        "status_code" => 20_000,
        "status_message" => "Ok.",
        "cost" => 0.002,
        "result_count" => 1,
        "path" => ["v3", "serp", "google", "organic", "live", "advanced"],
        "data" => %{"api" => "serp", "se" => "google", "se_type" => "organic"},
        "result" => [
          %{
            "keyword" => "buty do biegania",
            "type" => "organic",
            "se_domain" => "google.pl",
            "location_code" => 2616,
            "language_code" => "pl",
            "items_count" => Enum.count(items),
            "items" => items
          }
        ]
      }
    })
  end

  defp organic_item(position) do
    %{
      "type" => "organic",
      "rank_group" => position,
      "rank_absolute" => position,
      "domain" => "strona-#{position}.example",
      "title" => "Wynik #{position}",
      "url" => "https://strona-#{position}.example/"
    }
  end

  defp failed_task_body(%{status_code: status_code, status_message: status_message}) do
    %{
      envelope(%{
        cost: 0,
        task: %{
          "status_code" => status_code,
          "status_message" => status_message,
          "cost" => 0,
          "result_count" => 0,
          "path" => ["v3"],
          "data" => %{},
          "result" => nil
        }
      })
      | "tasks_error" => 1
    }
  end

  defp task_without_message(tasks), do: Enum.map(tasks, &Map.delete(&1, "status_message"))

  defp locations_body do
    envelope(%{
      cost: 0,
      task: %{
        "status_code" => 20_000,
        "status_message" => "Ok.",
        "cost" => 0,
        "result_count" => 5,
        "path" => ["v3", "keywords_data", "google_ads", "locations", "pl"],
        "data" => %{"api" => "keywords_data", "function" => "locations", "se" => "google_ads"},
        "result" => [
          location(%{code: 2616, name: "Poland", parent: nil, type: "Country"}),
          location(%{code: 20_855, name: "Masovian Voivodeship,Poland", parent: 2616, type: "Region"}),
          location(%{code: 1_011_615, name: "Warsaw,Masovian Voivodeship,Poland", parent: 20_855, type: "City"}),
          location(%{code: 1_011_700, name: "Gdańsk,Pomeranian Voivodeship,Poland", parent: 20_856, type: "City"}),
          location(%{code: 1_011_800, name: "Łódź,Lodz Voivodeship,Poland", parent: 20_857, type: "City"})
        ]
      }
    })
  end

  defp location(%{code: code, name: name, parent: parent, type: type}) do
    %{
      "location_code" => code,
      "location_name" => name,
      "location_code_parent" => parent,
      "country_iso_code" => "PL",
      "location_type" => type
    }
  end
end
