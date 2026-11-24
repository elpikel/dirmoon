defmodule Dirmoon.DataForSEO.HTTP do
  @moduledoc """
  The DataForSEO v3 adapter over HTTP (Req), one task per Live request.

  Configured by `config :dirmoon, Dirmoon.DataForSEO.HTTP` with `login`,
  `password`, `base_url` and extra `req_options`. Credentials travel only in
  the Basic auth header; `raw` is the response body and errors carry
  DataForSEO's status message, so neither holds them.

  DataForSEO answers HTTP 200 for most failures: success is a top-level and a
  task `status_code` of 20000. "No Search Results." counts as an empty answer.
  """

  @behaviour Dirmoon.DataForSEO

  alias Dirmoon.DataForSEO

  @default_base_url "https://api.dataforseo.com"
  @receive_timeout 130_000
  @ok_status 20_000
  @no_search_results_status 40_102
  @currency "USD"
  @serp_depth 10
  @organic_type "organic"
  @city_location_type "City"

  @impl DataForSEO
  def keyword_ideas(%{seeds: seeds, location_code: location_code, language_code: language_code}) do
    with :ok <- DataForSEO.ensure_within_limit(seeds, DataForSEO.max_seeds()),
         {:ok, answer} <-
           post_task(%{
             path: "/v3/keywords_data/google_ads/keywords_for_keywords/live",
             task: %{keywords: seeds, location_code: location_code, language_code: language_code}
           }) do
      {:ok, with_rows(answer, &keyword_rows/1)}
    end
  end

  @impl DataForSEO
  def search_volumes(%{phrases: phrases, location_code: location_code, language_code: language_code}) do
    with :ok <- DataForSEO.ensure_within_limit(phrases, DataForSEO.max_phrases()),
         {:ok, answer} <-
           post_task(%{
             path: "/v3/keywords_data/google_ads/search_volume/live",
             task: %{keywords: phrases, location_code: location_code, language_code: language_code}
           }) do
      {:ok, with_rows(answer, &keyword_rows/1)}
    end
  end

  @impl DataForSEO
  def serp_top10(%{phrase: phrase, location_code: location_code, language_code: language_code}) do
    with {:ok, answer} <-
           post_task(%{
             path: "/v3/serp/google/organic/live/advanced",
             task: %{keyword: phrase, location_code: location_code, language_code: language_code, depth: @serp_depth}
           }) do
      {:ok, with_rows(answer, &serp_rows/1)}
    end
  end

  defguardp ascii_letter?(character) when character in ?a..?z or character in ?A..?Z

  @impl DataForSEO
  def find_location(%{city: city, country_code: <<first, second>> = country_code})
      when ascii_letter?(first) and ascii_letter?(second) do
    with {:ok, %{result: locations, raw: raw, cost: cost}} <-
           send_request(method: :get, url: "/v3/keywords_data/google_ads/locations/#{String.downcase(country_code)}"),
         %{"location_code" => location_code, "location_name" => name} <- find_city(locations, city) do
      {:ok, %{location_code: location_code, name: name, raw: raw, cost: cost}}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def find_location(%{country_code: _invalid_country_code}), do: {:error, :invalid_country_code}

  defp post_task(%{path: path, task: task}), do: send_request(method: :post, url: path, json: [task])

  defp send_request(request_options) do
    config = Application.get_env(:dirmoon, __MODULE__, [])

    [
      base_url: Keyword.get(config, :base_url, @default_base_url),
      auth: {:basic, "#{Keyword.get(config, :login)}:#{Keyword.get(config, :password)}"},
      receive_timeout: @receive_timeout,
      retry: false
    ]
    |> Keyword.merge(Keyword.get(config, :req_options, []))
    |> Req.request(request_options)
    |> task_answer()
  end

  defp task_answer(
         {:ok, %Req.Response{status: 200, body: %{"status_code" => @ok_status, "tasks" => [task | _rest]} = body}}
       ), do: task_result(task, body)

  defp task_answer({:ok, %Req.Response{status: 200, body: %{"status_code" => @ok_status}}}),
    do: failure("response without a task")

  defp task_answer({:ok, %Req.Response{body: %{"status_message" => message}}}) when is_binary(message),
    do: failure(message)

  defp task_answer({:ok, %Req.Response{status: status}}), do: failure("HTTP #{status}")
  defp task_answer({:error, exception}), do: exception |> Exception.message() |> failure()

  defp task_result(%{"status_code" => @ok_status} = task, body), do: answer(%{result: task["result"], body: body})
  defp task_result(%{"status_code" => @no_search_results_status}, body), do: answer(%{result: [], body: body})
  defp task_result(%{"status_message" => message}, _body) when is_binary(message), do: failure(message)
  defp task_result(task, _body), do: failure("status #{task["status_code"]}")

  defp answer(%{result: result, body: body}) do
    {:ok, %{result: List.wrap(result), raw: body, cost: body |> Map.get("cost") |> cost()}}
  end

  defp failure(message), do: {:error, "DataForSEO: #{message}"}

  defp with_rows(%{result: result, raw: raw, cost: cost}, to_rows), do: %{rows: to_rows.(result), raw: raw, cost: cost}

  defp keyword_rows(items), do: Enum.map(items, &keyword_row/1)

  defp keyword_row(item) do
    %{
      phrase: item["keyword"],
      search_volume: item["search_volume"],
      cpc: decimal(item["cpc"]),
      currency: @currency,
      monthly_searches: item["monthly_searches"] |> List.wrap() |> Enum.map(&monthly_search/1)
    }
  end

  defp monthly_search(month) do
    %{year: month["year"], month: month["month"], search_volume: month["search_volume"]}
  end

  defp serp_rows([%{"items" => items} | _rest]) when is_list(items) do
    items
    |> Enum.filter(&(&1["type"] == @organic_type))
    |> Enum.sort_by(& &1["rank_group"])
    |> Enum.take(@serp_depth)
    |> Enum.map(&%{position: &1["rank_group"], url: &1["url"], domain: &1["domain"], title: &1["title"]})
  end

  defp serp_rows(_result), do: []

  defp find_city(locations, city) do
    wanted = comparable(city)

    Enum.find(locations, fn location ->
      location["location_type"] == @city_location_type and city_part(location["location_name"]) == wanted
    end)
  end

  defp city_part(location_name) do
    location_name
    |> to_string()
    |> String.split(",", parts: 2)
    |> List.first()
    |> comparable()
  end

  defp comparable(name) do
    name
    |> String.trim()
    |> String.downcase()
    |> String.replace("ł", "l")
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
  end

  defp cost(nil), do: Decimal.new(0)
  defp cost(value), do: decimal(value)

  defp decimal(nil), do: nil
  defp decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp decimal(value) when is_integer(value), do: Decimal.new(value)
  defp decimal(value) when is_binary(value), do: Decimal.new(value)
end
