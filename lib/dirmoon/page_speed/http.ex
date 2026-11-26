defmodule Dirmoon.PageSpeed.HTTP do
  @moduledoc """
  The Google PageSpeed Insights v5 adapter over HTTP (Req): one
  `GET /pagespeedonline/v5/runPagespeed` per check, as a phone
  (`strategy=mobile`), with the performance and accessibility categories
  (the accessibility one holds the `meta-viewport` and `target-size`
  checks).

  Configured by `config :dirmoon, Dirmoon.PageSpeed.HTTP` with `api_key`,
  `base_url` and extra `req_options`. The key travels only in the request's
  address; `raw` is Google's response body cut down to what the result is
  read from, which echoes the page checked, not the key, and an error's
  message has the key cut out, so neither holds it.

  Google's answer weighs 0.5–2 MB, mostly screenshots (base64 images in
  the `final-screenshot`, `screenshot-thumbnails` and `full-page-screenshot`
  checks and in `lighthouseResult.fullPageScreenshot`), the `i18n` strings
  and each check's `details`. `raw` keeps only `loadingExperience`,
  `originLoadingExperience` and, of `lighthouseResult`, the
  `lighthouseVersion`, `runtimeError`, `categories` and, for each check in
  `audits`, its `id`, `score`, `scoreDisplayMode`, `numericValue` and
  `displayValue`: a few tens of KB. Google takes 10–30 seconds to load a page, so the answer is awaited
  for up to two minutes, and a failed request is not retried here.

  Google's error bodies are undocumented for this API, so they are read by
  their shape (`error.code`, `error.status`, `error.message`): HTTP 429 or
  `RESOURCE_EXHAUSTED` is the quota; HTTP 401 or 403, `UNAUTHENTICATED`,
  `PERMISSION_DENIED`, or a message about the API key is a refused key; a
  message saying Lighthouse returned an error, or a `runtimeError` in a
  200 answer, means Google could not load the page.
  """

  @behaviour Dirmoon.PageSpeed

  @default_base_url "https://www.googleapis.com"
  @path "/pagespeedonline/v5/runPagespeed"
  @receive_timeout 120_000
  @strategy "mobile"
  @categories ["performance", "accessibility"]
  @quota_status "RESOURCE_EXHAUSTED"
  @refused_key_statuses ["UNAUTHENTICATED", "PERMISSION_DENIED"]
  @refused_key_http_statuses [401, 403]
  @quota_http_status 429
  @lighthouse_error_marker "Lighthouse returned error"
  @api_key_marker "API key"
  @no_runtime_error "NO_ERROR"
  @key_placeholder "[key]"
  @passing_score 0.9
  @not_scored_modes ["notApplicable", "manual", "informative", "error"]
  @phone_check_ids ["viewport-insight", "meta-viewport", "target-size"]
  @kept_answer_keys ["loadingExperience", "originLoadingExperience"]
  @kept_lighthouse_keys ["lighthouseVersion", "runtimeError", "categories"]
  @kept_check_keys ["id", "score", "scoreDisplayMode", "numericValue", "displayValue"]
  @field_measures [
    {"LARGEST_CONTENTFUL_PAINT_MS", "largest_contentful_paint"},
    {"INTERACTION_TO_NEXT_PAINT", "interaction_to_next_paint"},
    {"CUMULATIVE_LAYOUT_SHIFT_SCORE", "cumulative_layout_shift"}
  ]

  @impl Dirmoon.PageSpeed
  def check(%{url: url}) do
    config = Application.get_env(:dirmoon, __MODULE__, [])
    api_key = Keyword.fetch!(config, :api_key)

    [
      base_url: Keyword.get(config, :base_url, @default_base_url),
      url: @path,
      params: [url: url, key: api_key, strategy: @strategy] ++ Enum.map(@categories, &{:category, &1}),
      receive_timeout: @receive_timeout,
      retry: false
    ]
    |> Req.request(Keyword.get(config, :req_options, []))
    |> answer(api_key)
  end

  defp answer({:ok, %Req.Response{status: 200, body: %{"lighthouseResult" => %{} = lighthouse} = body}}, _api_key) do
    case lighthouse["runtimeError"] do
      %{"code" => code} when is_binary(code) and code != @no_runtime_error -> {:error, :page_unreachable}
      _no_runtime_error -> {:ok, %{result: result(body, lighthouse), raw: stored_raw(body, lighthouse)}}
    end
  end

  defp answer({:ok, %Req.Response{status: 200}}, _api_key), do: failed("answer without a Lighthouse result")

  defp answer({:ok, %Req.Response{status: status, body: %{"error" => %{} = error}}}, api_key),
    do: refusal(status, %{status: error["status"], message: message_without_key(error["message"], api_key)})

  defp answer({:ok, %Req.Response{status: status}}, _api_key), do: failed("HTTP #{status}")
  defp answer({:error, exception}, _api_key), do: exception |> Exception.message() |> failed()

  defp refusal(@quota_http_status, _error), do: {:error, :page_speed_quota_exceeded}
  defp refusal(_http_status, %{status: @quota_status}), do: {:error, :page_speed_quota_exceeded}
  defp refusal(http_status, _error) when http_status in @refused_key_http_statuses, do: {:error, :page_speed_key_rejected}

  defp refusal(_http_status, %{status: status}) when status in @refused_key_statuses,
    do: {:error, :page_speed_key_rejected}

  defp refusal(http_status, %{message: message}) do
    cond do
      String.contains?(message, @lighthouse_error_marker) -> {:error, :page_unreachable}
      String.contains?(message, @api_key_marker) -> {:error, :page_speed_key_rejected}
      true -> failed("HTTP #{http_status}: #{message}")
    end
  end

  defp message_without_key(message, api_key) when is_binary(message),
    do: String.replace(message, api_key, @key_placeholder)

  defp message_without_key(_missing, _api_key), do: ""

  defp failed(message), do: {:error, {:page_speed_failed, "PageSpeed: " <> message}}

  defp stored_raw(body, lighthouse) do
    lighthouse_kept =
      lighthouse
      |> Map.take(@kept_lighthouse_keys)
      |> Map.put("audits", stored_checks(lighthouse["audits"]))

    body
    |> Map.take(@kept_answer_keys)
    |> Map.put("lighthouseResult", lighthouse_kept)
  end

  defp stored_checks(%{} = checks), do: Map.new(checks, fn {id, check} -> {id, stored_check(check)} end)
  defp stored_checks(_missing), do: %{}

  defp stored_check(%{} = check), do: Map.take(check, @kept_check_keys)
  defp stored_check(_odd), do: %{}

  defp result(body, lighthouse) do
    checks = dig(lighthouse, ["audits"])

    %{
      "performance_score" => lighthouse |> dig(["categories", "performance", "score"]) |> percent(),
      "largest_contentful_paint_ms" => checks |> dig(["largest-contentful-paint", "numericValue"]) |> whole(),
      "total_blocking_time_ms" => checks |> dig(["total-blocking-time", "numericValue"]) |> whole(),
      "cumulative_layout_shift" => checks |> dig(["cumulative-layout-shift", "numericValue"]) |> number(),
      "lighthouse_version" => lighthouse |> dig(["lighthouseVersion"]) |> text(),
      "field" => field(body),
      "phone_checks" => phone_checks(checks)
    }
  end

  defp field(body) do
    page_scope = if dig(body, ["loadingExperience", "origin_fallback"]) == true, do: "origin", else: "page"

    for {google_name, name} <- @field_measures,
        measure = field_measure(body, %{google_name: google_name, page_scope: page_scope}),
        measure != nil,
        into: %{},
        do: {name, measure}
  end

  defp field_measure(body, %{google_name: google_name, page_scope: page_scope}) do
    page_measure = dig(body, ["loadingExperience", "metrics", google_name])
    origin_measure = dig(body, ["originLoadingExperience", "metrics", google_name])

    cond do
      reported?(page_measure) -> measure(page_measure, page_scope)
      reported?(origin_measure) -> measure(origin_measure, "origin")
      true -> nil
    end
  end

  defp reported?(%{"percentile" => percentile}), do: is_number(percentile)
  defp reported?(_missing), do: false

  defp measure(%{"percentile" => percentile} = measure, scope),
    do: %{"percentile" => percentile, "category" => text(measure["category"]), "scope" => scope}

  defp phone_checks(%{} = checks) do
    for id <- @phone_check_ids, %{} = check <- [checks[id]], do: %{"id" => id, "passed" => passed(check)}
  end

  defp phone_checks(_missing), do: []

  defp passed(%{"scoreDisplayMode" => mode}) when mode in @not_scored_modes, do: nil
  defp passed(%{"score" => score}) when is_number(score), do: score >= @passing_score
  defp passed(_unscored), do: nil

  defp dig(value, []), do: value
  defp dig(%{} = map, [key | rest]), do: map |> Map.get(key) |> dig(rest)
  defp dig(_other, _keys), do: nil

  defp percent(score) when is_number(score), do: round(score * 100)
  defp percent(_missing), do: nil

  defp whole(value) when is_number(value), do: round(value)
  defp whole(_missing), do: nil

  defp number(value) when is_number(value), do: value
  defp number(_missing), do: nil

  defp text(value) when is_binary(value), do: value
  defp text(_missing), do: nil
end
