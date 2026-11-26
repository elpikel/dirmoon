defmodule Dirmoon.DataForSEO.HTTP do
  @moduledoc """
  The DataForSEO v3 adapter over HTTP (Req), one task per Live request.

  Configured by `config :dirmoon, Dirmoon.DataForSEO.HTTP` with `login`,
  `password`, `base_url` and extra `req_options`. Credentials travel only in
  the Basic auth header; `raw` is the response body and errors carry
  DataForSEO's status message, so neither holds them.

  DataForSEO answers HTTP 200 for most failures: success is a top-level and a
  task `status_code` of 20000. "No Search Results." counts as an empty answer.
  A failed task is an error carrying only DataForSEO's message, except for
  ranked phrases, a Business Profile and linking sites, below.

  Ranked phrases come from DataForSEO Labs' Ranked Keywords endpoint,
  organic results only, and a Business Profile from Business Data's Google
  My Business Info endpoint (the business name sent as the `keyword`). Both
  cover fewer locations than the app offers and their exact answer for one
  they don't cover is undocumented, so any failure DataForSEO reports for
  the task itself is `{:ranked_phrases_unavailable, %{message:, raw:, cost:}}`
  (or `:business_profile_unavailable`, `:linking_sites_unavailable`), with
  the cost it reports. That includes 40204, the account having no
  subscription to that API, whether DataForSEO reports it for the task or
  for the whole request: asking again can't help until the owner
  subscribes. Two kinds of task failure
  are an error to retry instead, like a failed request: any other refusal
  of the account's access, funds or rate (40100–40199, 40200–40299), and
  DataForSEO's internal errors (50000–59999), which may pass. A
  Business Profile lookup that finds nothing (no item, no result, or "No
  Search Results.") is `profile: nil`. The indexed page
  count is the `se_results_count` of a `site:` search on the organic SERP
  endpoint.

  Linking sites come from the Backlinks API's bulk referring domains
  endpoint, all domains in one task (`targets`): each item's
  `referring_main_domains` (distinct sites, not subdomains), matched to the
  domain sent by the item's `target`, never by its place in the list, since
  DataForSEO doesn't say the order is kept. An item without a whole,
  non-negative count, and a domain with no item, give no row.
  """

  @behaviour Dirmoon.DataForSEO

  alias Dirmoon.DataForSEO
  alias Dirmoon.Spelling
  alias Dirmoon.WebPage.HostName

  @default_base_url "https://api.dataforseo.com"
  @receive_timeout 130_000
  @ok_status 20_000
  @no_search_results_status 40_102
  @account_refusal_statuses 40_100..40_299
  @no_subscription_status 40_204
  @internal_error_statuses 50_000..59_999
  @currency "USD"
  @serp_depth 10
  @organic_type "organic"
  @city_location_type "City"
  @country_location_type "Country"
  @locations_path "/v3/keywords_data/google_ads/locations"
  @google_redirect_prefix "https://google.com/goto?"
  @breadcrumb_separator "›"

  @impl DataForSEO
  def phrase_ideas(%{seeds: seeds, location_code: location_code, language_code: language_code}) do
    with :ok <- DataForSEO.ensure_within_limit(seeds, DataForSEO.max_seeds()),
         {:ok, answer} <-
           post_task(%{
             path: "/v3/keywords_data/google_ads/keywords_for_keywords/live",
             task: %{keywords: seeds, location_code: location_code, language_code: language_code}
           }) do
      {:ok, with_rows(answer, &phrase_rows/1)}
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
      {:ok, with_rows(answer, &phrase_rows/1)}
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

  @impl DataForSEO
  def ranked_phrases(%{domain: domain, location_code: location_code, language_code: language_code, limit: limit}) do
    with {:ok, answer} <-
           post_task(%{
             path: "/v3/dataforseo_labs/google/ranked_keywords/live",
             task: %{
               target: domain,
               location_code: location_code,
               language_code: language_code,
               item_types: [@organic_type],
               limit: limit
             },
             on_failure: unavailable(:ranked_phrases_unavailable)
           }) do
      {:ok, with_rows(answer, &ranked_phrase_rows/1)}
    end
  end

  @impl DataForSEO
  def indexed_page_count(%{domain: domain, location_code: location_code, language_code: language_code}) do
    with {:ok, %{result: result, raw: raw, cost: cost}} <-
           post_task(%{
             path: "/v3/serp/google/organic/live/advanced",
             task: %{
               keyword: "site:" <> domain,
               location_code: location_code,
               language_code: language_code,
               depth: @serp_depth
             }
           }) do
      {:ok, %{count: results_count(result), raw: raw, cost: cost}}
    end
  end

  @impl DataForSEO
  def business_profile(%{name: name, location_code: location_code, language_code: language_code}) do
    with {:ok, %{result: result, raw: raw, cost: cost}} <-
           post_task(%{
             path: "/v3/business_data/google/my_business_info/live",
             task: %{
               keyword: String.replace(name, "%", "%25"),
               location_code: location_code,
               language_code: language_code
             },
             on_failure: unavailable(:business_profile_unavailable)
           }) do
      {:ok, %{profile: business_profile_from(result), raw: raw, cost: cost}}
    end
  end

  @impl DataForSEO
  def linking_sites(%{domains: domains}) when is_list(domains) do
    targets = domains |> Enum.map(&bare_domain/1) |> Enum.uniq()

    cond do
      targets == [] ->
        {:ok, %{rows: [], raw: %{}, cost: Decimal.new(0)}}

      length(targets) > DataForSEO.max_linking_sites_domains() ->
        {:error, :too_many_domains}

      true ->
        with {:ok, answer} <-
               post_task(%{
                 path: "/v3/backlinks/bulk_referring_domains/live",
                 task: %{targets: targets},
                 on_failure: unavailable(:linking_sites_unavailable)
               }) do
          {:ok, with_rows(answer, &linking_sites_rows(&1, targets))}
        end
    end
  end

  defguardp ascii_letter?(character) when character in ?a..?z or character in ?A..?Z

  @impl DataForSEO
  def find_location(%{city: city, country_code: <<first, second>> = country_code})
      when ascii_letter?(first) and ascii_letter?(second) do
    with {:ok, %{result: locations, raw: raw, cost: cost}} <-
           send_request(method: :get, url: "#{@locations_path}/#{String.downcase(country_code)}"),
         %{"location_code" => location_code, "location_name" => name} <- find_city(locations, city) do
      {:ok, %{location_code: location_code, name: name, raw: raw, cost: cost}}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def find_location(%{country_code: _invalid_country_code}), do: {:error, :invalid_country_code}

  @impl DataForSEO
  def countries do
    with {:ok, %{result: locations}} <- send_request(method: :get, url: @locations_path) do
      {:ok,
       for(
         %{
           "location_type" => @country_location_type,
           "location_code" => location_code,
           "location_name" => name,
           "country_iso_code" => country_code
         }
         when is_integer(location_code) and is_binary(name) and is_binary(country_code) <- locations,
         do: %{country_code: country_code, location_code: location_code, name: name}
       )}
    end
  end

  @impl DataForSEO
  def languages do
    with {:ok, %{result: languages}} <-
           send_request(method: :get, url: "/v3/keywords_data/google_ads/languages") do
      {:ok,
       for(
         %{"language_code" => language_code, "language_name" => name}
         when is_binary(language_code) and is_binary(name) <- languages,
         do: %{language_code: language_code, name: name}
       )}
    end
  end

  defp post_task(%{path: path, task: task} = request),
    do: send_request([method: :post, url: path, json: [task]], Map.get(request, :on_failure, &failed_answer/2))

  defp send_request(request_options, on_failure \\ &failed_answer/2) do
    config = Application.get_env(:dirmoon, __MODULE__, [])

    [
      base_url: Keyword.get(config, :base_url, @default_base_url),
      auth: {:basic, "#{Keyword.get(config, :login)}:#{Keyword.get(config, :password)}"},
      receive_timeout: @receive_timeout,
      retry: false
    ]
    |> Keyword.merge(Keyword.get(config, :req_options, []))
    |> Req.request(request_options)
    |> task_answer(on_failure)
  end

  defp task_answer(
         {:ok, %Req.Response{status: 200, body: %{"status_code" => @ok_status, "tasks" => [task | _rest]} = body}},
         on_failure
       ), do: task_result(task, %{body: body, on_failure: on_failure})

  defp task_answer({:ok, %Req.Response{status: 200, body: %{"status_code" => @ok_status}}}, _on_failure),
    do: failure("response without a task")

  defp task_answer(
         {:ok, %Req.Response{status: 200, body: %{"status_code" => @no_subscription_status} = body}},
         on_failure
       ), do: on_failure.(body, body)

  defp task_answer({:ok, %Req.Response{body: %{"status_message" => message}}}, _on_failure) when is_binary(message),
    do: failure(message)

  defp task_answer({:ok, %Req.Response{status: status}}, _on_failure), do: failure("HTTP #{status}")
  defp task_answer({:error, exception}, _on_failure), do: exception |> Exception.message() |> failure()

  defp task_result(%{"status_code" => @ok_status} = task, %{body: body}),
    do: answer(%{result: task["result"], body: body})

  defp task_result(%{"status_code" => @no_search_results_status}, %{body: body}), do: answer(%{result: [], body: body})
  defp task_result(task, %{body: body, on_failure: on_failure}), do: on_failure.(task, body)

  defp failed_answer(task, _body), do: task |> failure_message() |> failure()

  defp unavailable(reason) do
    fn
      %{"status_code" => status_code} = task, body when status_code in @internal_error_statuses ->
        failed_answer(task, body)

      %{"status_code" => status_code} = task, body
      when status_code in @account_refusal_statuses and status_code != @no_subscription_status ->
        failed_answer(task, body)

      task, body ->
        {:error, message} = task |> failure_message() |> failure()
        {:error, {reason, %{message: message, raw: body, cost: body |> Map.get("cost") |> cost()}}}
    end
  end

  defp failure_message(%{"status_message" => message}) when is_binary(message), do: message
  defp failure_message(task), do: "status #{task["status_code"]}"

  defp answer(%{result: result, body: body}) do
    {:ok, %{result: List.wrap(result), raw: body, cost: body |> Map.get("cost") |> cost()}}
  end

  defp failure(message), do: {:error, "DataForSEO: #{message}"}

  defp with_rows(%{result: result, raw: raw, cost: cost}, to_rows), do: %{rows: to_rows.(result), raw: raw, cost: cost}

  defp phrase_rows(items), do: Enum.map(items, &phrase_row/1)

  defp phrase_row(item) do
    %{
      phrase: item["keyword"],
      search_volume: item["search_volume"],
      cpc: decimal(item["cpc"]),
      currency: @currency,
      trend: item["monthly_searches"] |> List.wrap() |> Enum.map(&trend_month/1)
    }
  end

  defp trend_month(month) do
    %{year: month["year"], month: month["month"], search_volume: month["search_volume"]}
  end

  @doc """
  The top-10 rows of a stored SERP response body (a snapshot's `raw`), parsed
  as `serp_top10/1` parses a fresh one, so a change in the parsing can be
  applied to stored snapshots without buying them again.
  """
  def serp_rows_from_raw(%{"tasks" => [%{"result" => result} | _rest]}), do: result |> List.wrap() |> serp_rows()
  def serp_rows_from_raw(_raw), do: []

  defp serp_rows([%{"items" => items} | _rest]) when is_list(items) do
    items
    |> Enum.filter(&(&1["type"] == @organic_type))
    |> Enum.sort_by(& &1["rank_group"])
    |> Enum.take(@serp_depth)
    |> Enum.map(&serp_row/1)
  end

  defp serp_rows(_result), do: []

  defp linking_sites_rows([%{"items" => items} | _rest], targets) when is_list(items) do
    counts =
      for %{"target" => target, "referring_main_domains" => count}
          when is_binary(target) and is_integer(count) and count >= 0 <-
            items,
          into: %{},
          do: {bare_domain(target), count}

    for target <- targets, is_map_key(counts, target), do: %{domain: target, linking_sites: Map.fetch!(counts, target)}
  end

  defp linking_sites_rows(_result, _targets), do: []

  defp bare_domain(domain), do: domain |> String.trim() |> HostName.bare()

  defp ranked_phrase_rows([%{"items" => items} | _rest]) when is_list(items),
    do: Enum.flat_map(items, &ranked_phrase_row/1)

  defp ranked_phrase_rows(_result), do: []

  defp ranked_phrase_row(%{
         "keyword_data" => %{"keyword" => phrase} = phrase_data,
         "ranked_serp_element" => %{"serp_item" => %{"type" => @organic_type, "rank_group" => position, "url" => url}}
       })
       when is_binary(phrase) and is_integer(position) and is_binary(url),
       do: [%{phrase: phrase, position: position, url: url, search_volume: monthly_volume(phrase_data)}]

  defp ranked_phrase_row(_incomplete_item), do: []

  defp monthly_volume(%{"keyword_info" => %{"search_volume" => search_volume}}) when is_integer(search_volume),
    do: search_volume

  defp monthly_volume(_phrase_data), do: nil

  defp business_profile_from([%{"items" => [%{} = item | _rest]} | _results]) do
    rating = if is_map(item["rating"]), do: item["rating"], else: %{}

    %{
      title: text(item["title"]),
      address: text(item["address"]),
      phone: text(item["phone"]),
      url: text(item["url"]),
      domain: text(item["domain"]),
      rating: number(rating["value"]),
      votes: whole_number(rating["votes_count"]),
      claimed: boolean(item["is_claimed"])
    }
  end

  defp business_profile_from(_nothing_found), do: nil

  defp text(value) when is_binary(value), do: value
  defp text(_other), do: nil

  defp number(value) when is_number(value), do: value
  defp number(_other), do: nil

  defp whole_number(value) when is_integer(value), do: value
  defp whole_number(_other), do: nil

  defp boolean(value) when is_boolean(value), do: value
  defp boolean(_other), do: nil

  defp results_count([%{"se_results_count" => count} | _rest]) when is_integer(count) and count > 0, do: count
  defp results_count(_result), do: 0

  # Google sometimes wraps every result in a `google.com/goto?url=…` redirect,
  # and DataForSEO then reports `google.com` as the domain. The real site is
  # in the breadcrumb ("https://www.site.pl › path") or the website name.
  defp serp_row(%{"url" => @google_redirect_prefix <> _token} = item) do
    site = breadcrumb_site(item["breadcrumb"])

    %{
      position: item["rank_group"],
      url: (site && site.url) || item["url"],
      domain: (site && site.domain) || item["website_name"] || item["domain"],
      title: item["title"]
    }
  end

  defp serp_row(item) do
    %{position: item["rank_group"], url: item["url"], domain: item["domain"], title: item["title"]}
  end

  defp breadcrumb_site(breadcrumb) when is_binary(breadcrumb) do
    address = breadcrumb |> String.split(@breadcrumb_separator, parts: 2) |> List.first() |> String.trim()

    case URI.parse(address) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        %{url: address, domain: String.replace_prefix(host, "www.", "")}

      _not_an_address ->
        nil
    end
  end

  defp breadcrumb_site(_missing), do: nil

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
    |> Spelling.without_diacritics()
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
