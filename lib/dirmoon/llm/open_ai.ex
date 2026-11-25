defmodule Dirmoon.LLM.OpenAI do
  @moduledoc """
  The OpenAI adapter for the LLM seam: one Responses API request per
  structured request, answered as JSON that follows the request's schema
  (Structured Outputs, strict mode).

  Configured by `config :dirmoon, Dirmoon.LLM.OpenAI` with `api_key`, `model`,
  `prices` (USD per million tokens, by model), `base_url` and extra
  `req_options`. The key travels only in the Authorization header. The cost
  of a request is counted from the token usage OpenAI reports and the
  configured prices, so a model without prices is refused before any request
  is sent. Requests are not stored at OpenAI (`store: false`).
  """

  @behaviour Dirmoon.LLM

  @default_base_url "https://api.openai.com"
  @receive_timeout 300_000
  @tokens_per_price_unit 1_000_000
  @cost_decimal_places 6
  @completed_status "completed"
  @message_type "message"
  @output_text_type "output_text"
  @refusal_type "refusal"
  @object_type "object"

  @impl Dirmoon.LLM
  def structured(%{task: task, system: system, prompt: prompt, schema: schema}) do
    config = Application.get_env(:dirmoon, __MODULE__, [])
    model = Keyword.get(config, :model)

    with {:ok, prices} <- prices_for(config, model),
         {:ok, body} <-
           post(config, %{
             model: model,
             instructions: system,
             input: prompt,
             store: false,
             text: %{format: %{type: "json_schema", name: to_string(task), strict: true, schema: strict_schema(schema)}}
           }),
         {:ok, answer} <- answer(body) do
      {:ok, answer, cost(body, prices)}
    end
  end

  defp prices_for(config, model) do
    case config |> Keyword.get(:prices, %{}) |> Map.get(model) do
      %{input: _input, cached_input: _cached_input, output: _output} = prices -> {:ok, prices}
      nil -> failure("no prices for model #{model}")
    end
  end

  defp post(config, body) do
    [
      base_url: Keyword.get(config, :base_url, @default_base_url),
      auth: {:bearer, Keyword.get(config, :api_key)},
      receive_timeout: @receive_timeout,
      retry: false
    ]
    |> Keyword.merge(Keyword.get(config, :req_options, []))
    |> Req.post(url: "/v1/responses", json: body)
    |> response_body()
  end

  defp response_body({:ok, %Req.Response{status: 200, body: body}}) when is_map(body), do: {:ok, body}

  defp response_body({:ok, %Req.Response{body: %{"error" => %{"message" => message}}}}) when is_binary(message),
    do: failure(message)

  # OpenAI sends some error bodies (a rejected key) as JSON under a text/plain content type.
  defp response_body({:ok, %Req.Response{status: status, body: body}}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"error" => %{"message" => message}}} when is_binary(message) -> failure(message)
      _other -> failure("HTTP #{status}")
    end
  end

  defp response_body({:ok, %Req.Response{status: status}}), do: failure("HTTP #{status}")
  defp response_body({:error, exception}), do: exception |> Exception.message() |> failure()

  defp answer(%{"status" => @completed_status, "output" => output}) when is_list(output) do
    output
    |> Enum.filter(&(&1["type"] == @message_type))
    |> Enum.flat_map(&List.wrap(&1["content"]))
    |> content_answer()
  end

  defp answer(%{"status" => "incomplete"} = body) do
    failure("answer cut short (#{get_in(body, ["incomplete_details", "reason"]) || "unknown reason"})")
  end

  defp answer(%{"error" => %{"message" => message}}) when is_binary(message), do: failure(message)
  defp answer(_body), do: failure("answer has no content")

  defp content_answer(parts) do
    refusal = Enum.find(parts, &(&1["type"] == @refusal_type))
    text = Enum.find(parts, &(&1["type"] == @output_text_type))

    cond do
      refusal -> failure("the model refused to answer")
      text -> decoded_answer(text["text"])
      true -> failure("answer has no content")
    end
  end

  defp decoded_answer(text) do
    case Jason.decode(to_string(text)) do
      {:ok, answer} when is_map(answer) -> {:ok, answer}
      _invalid -> failure("the answer is not a JSON object")
    end
  end

  defp failure(message), do: {:error, "OpenAI: #{message}"}

  # Strict mode wants `additionalProperties: false` on every object; the
  # Steps' schemas already list every property as required.
  defp strict_schema(schema) do
    schema
    |> Jason.encode!()
    |> Jason.decode!()
    |> close_objects()
  end

  defp close_objects(%{"type" => @object_type} = schema) do
    schema
    |> Map.new(fn {key, value} -> {key, close_objects(value)} end)
    |> Map.put("additionalProperties", false)
  end

  defp close_objects(schema) when is_map(schema), do: Map.new(schema, fn {key, value} -> {key, close_objects(value)} end)
  defp close_objects(schemas) when is_list(schemas), do: Enum.map(schemas, &close_objects/1)
  defp close_objects(value), do: value

  defp cost(body, prices) do
    input_tokens = token_count(body, ["usage", "input_tokens"])
    cached_tokens = min(token_count(body, ["usage", "input_tokens_details", "cached_tokens"]), input_tokens)
    output_tokens = token_count(body, ["usage", "output_tokens"])

    [
      {input_tokens - cached_tokens, prices.input},
      {cached_tokens, prices.cached_input},
      {output_tokens, prices.output}
    ]
    |> Enum.map(fn {tokens, price} -> price |> Decimal.new() |> Decimal.mult(tokens) end)
    |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
    |> Decimal.div(@tokens_per_price_unit)
    |> Decimal.round(@cost_decimal_places)
  end

  defp token_count(body, path) do
    case get_in(body, path) do
      count when is_integer(count) -> count
      _missing -> 0
    end
  end
end
