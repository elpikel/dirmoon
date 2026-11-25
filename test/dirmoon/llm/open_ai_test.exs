defmodule Dirmoon.LLM.OpenAITest do
  use ExUnit.Case, async: false

  alias Dirmoon.LLM.OpenAI

  test "a structured request returns the decoded answer and the cost counted from the token usage" do
    stub_json(
      completed_body(%{
        text: ~s({"seeds":["hotel dla psów"],"questions":["Ile to trwa?"]}),
        usage: %{"input_tokens" => 1_000, "input_tokens_details" => %{"cached_tokens" => 400}, "output_tokens" => 500}
      })
    )

    assert {:ok, answer, cost} = OpenAI.structured(seeds_request())

    assert answer == %{"seeds" => ["hotel dla psów"], "questions" => ["Ile to trwa?"]}
    # 600 fresh input tokens at $2, 400 cached at $0.10 and 500 output at $10 per million.
    assert Decimal.equal?(cost, Decimal.new("0.00624"))
  end

  test "the request goes to the responses endpoint with the key, the model, the texts and a strict schema" do
    stub_json(completed_body(%{text: "{}", usage: %{}}))

    OpenAI.structured(seeds_request())

    assert_received {:request, %{method: "POST", path: "/v1/responses", body: body, authorization: authorization}}
    assert authorization == "Bearer test-openai-key"

    assert Jason.decode!(body) == %{
             "model" => "gpt-6.2-sol",
             "instructions" => "Jesteś specjalistą SEO.",
             "input" => "Wymyśl frazy dla hotelu dla psów.",
             "store" => false,
             "text" => %{
               "format" => %{
                 "type" => "json_schema",
                 "name" => "seeds",
                 "strict" => true,
                 "schema" => %{
                   "type" => "object",
                   "additionalProperties" => false,
                   "required" => ["seeds", "niches"],
                   "properties" => %{
                     "seeds" => %{"type" => "array", "items" => %{"type" => "string"}, "minItems" => 10},
                     "niches" => %{
                       "type" => "array",
                       "items" => %{
                         "type" => "object",
                         "additionalProperties" => false,
                         "required" => ["name"],
                         "properties" => %{"name" => %{"type" => "string", "enum" => ["a", "b"]}}
                       }
                     }
                   }
                 }
               }
             }
           }
  end

  test "an answer without token usage costs nothing" do
    stub_json(completed_body(%{text: ~s({"seeds":[]}), usage: nil}))

    assert {:ok, %{"seeds" => []}, cost} = OpenAI.structured(seeds_request())
    assert Decimal.equal?(cost, Decimal.new(0))
  end

  test "the model set in config is the one asked and priced" do
    put_config(model: "gpt-6-luna")

    stub_json(completed_body(%{text: "{}", usage: %{"input_tokens" => 1_000_000, "output_tokens" => 1_000_000}}))

    assert {:ok, %{}, cost} = OpenAI.structured(seeds_request())

    assert_received {:request, %{body: body}}
    assert Jason.decode!(body)["model"] == "gpt-6-luna"
    assert Decimal.equal?(cost, Decimal.new("0.60"))
  end

  test "a model without configured prices is refused before any request" do
    put_config(model: "gpt-unknown")
    stub_json(completed_body(%{text: "{}", usage: %{}}))

    assert OpenAI.structured(seeds_request()) == {:error, "OpenAI: no prices for model gpt-unknown"}
    refute_received {:request, _request}
  end

  test "a refusal is an error" do
    stub_json(%{
      "status" => "completed",
      "output" => [%{"type" => "message", "content" => [%{"type" => "refusal", "refusal" => "I can't help."}]}]
    })

    assert OpenAI.structured(seeds_request()) == {:error, "OpenAI: the model refused to answer"}
  end

  test "an answer cut short is an error that names the reason" do
    stub_json(%{"status" => "incomplete", "incomplete_details" => %{"reason" => "max_output_tokens"}, "output" => []})

    assert OpenAI.structured(seeds_request()) == {:error, "OpenAI: answer cut short (max_output_tokens)"}
  end

  test "an answer cut short without a reason is still an error" do
    stub_json(%{"status" => "incomplete", "output" => []})

    assert OpenAI.structured(seeds_request()) == {:error, "OpenAI: answer cut short (unknown reason)"}
  end

  test "a failed response returns its error message" do
    stub_json(%{"status" => "failed", "error" => %{"code" => "server_error", "message" => "The model failed."}})

    assert OpenAI.structured(seeds_request()) == {:error, "OpenAI: The model failed."}
  end

  test "a completed response with no message is an error" do
    stub_json(%{"status" => "completed", "output" => [%{"type" => "reasoning", "summary" => []}]})

    assert OpenAI.structured(seeds_request()) == {:error, "OpenAI: answer has no content"}
  end

  test "a response in an unknown shape is an error" do
    stub_json(%{"status" => "queued"})

    assert OpenAI.structured(seeds_request()) == {:error, "OpenAI: answer has no content"}
  end

  test "text that is not a JSON object is an error" do
    stub_json(completed_body(%{text: "[1, 2]", usage: %{}}))
    assert OpenAI.structured(seeds_request()) == {:error, "OpenAI: the answer is not a JSON object"}

    stub_json(completed_body(%{text: "not json", usage: %{}}))
    assert OpenAI.structured(seeds_request()) == {:error, "OpenAI: the answer is not a JSON object"}
  end

  test "an HTTP error returns OpenAI's message" do
    stub_json(%{"error" => %{"message" => "Incorrect API key provided.", "type" => "invalid_request_error"}}, 401)

    assert OpenAI.structured(seeds_request()) == {:error, "OpenAI: Incorrect API key provided."}
  end

  test "an HTTP error without a message returns the status" do
    stub_json(%{"unexpected" => true}, 503)

    assert OpenAI.structured(seeds_request()) == {:error, "OpenAI: HTTP 503"}
  end

  test "an HTTP error sent as JSON in a plain-text body returns OpenAI's message" do
    stub_text(~s({"error": {"message": "Incorrect API key provided."}, "status": 401}), 401)

    assert OpenAI.structured(seeds_request()) == {:error, "OpenAI: Incorrect API key provided."}
  end

  test "an HTTP error with a plain-text body returns the status" do
    stub_text("Bad gateway", 502)
    assert OpenAI.structured(seeds_request()) == {:error, "OpenAI: HTTP 502"}

    stub_text(~s({"unexpected": true}), 502)
    assert OpenAI.structured(seeds_request()) == {:error, "OpenAI: HTTP 502"}
  end

  test "a transport failure returns its message" do
    Req.Test.stub(OpenAI, &Req.Test.transport_error(&1, :timeout))

    assert OpenAI.structured(seeds_request()) == {:error, "OpenAI: timeout"}
  end

  test "the key and the model come from the environment outside tests" do
    System.put_env(%{"OPENAI_API_KEY" => "sk-from-env", "OPENAI_MODEL" => "gpt-6.2-astra"})
    on_exit(fn -> Enum.each(~w(OPENAI_API_KEY OPENAI_MODEL), &System.delete_env/1) end)

    config = Config.Reader.read!("config/runtime.exs", env: :dev)

    assert get_in(config, [:dirmoon, :llm_adapter]) == OpenAI
    assert get_in(config, [:dirmoon, OpenAI, :api_key]) == "sk-from-env"
    assert get_in(config, [:dirmoon, OpenAI, :model]) == "gpt-6.2-astra"

    System.delete_env("OPENAI_MODEL")
    config = Config.Reader.read!("config/runtime.exs", env: :dev)

    assert get_in(config, [:dirmoon, OpenAI, :model]) == nil
    assert get_in(Config.Reader.read!("config/runtime.exs", env: :test), [:dirmoon, :llm_adapter]) == nil
  end

  defp seeds_request do
    %{
      task: :seeds,
      system: "Jesteś specjalistą SEO.",
      prompt: "Wymyśl frazy dla hotelu dla psów.",
      schema: %{
        type: "object",
        properties: %{
          seeds: %{type: "array", items: %{type: "string"}, minItems: 10},
          niches: %{
            type: "array",
            items: %{type: "object", properties: %{name: %{type: "string", enum: ["a", "b"]}}, required: ["name"]}
          }
        },
        required: ["seeds", "niches"]
      },
      input: %{description: "Hotel dla psów", city: nil, priority_services: []}
    }
  end

  defp completed_body(%{text: text, usage: usage}) do
    %{
      "id" => "resp_test",
      "status" => "completed",
      "output" => [
        %{"type" => "reasoning", "summary" => []},
        %{"type" => "message", "role" => "assistant", "content" => [%{"type" => "output_text", "text" => text}]}
      ],
      "usage" => usage
    }
  end

  defp put_config(overrides) do
    original = Application.get_env(:dirmoon, OpenAI)
    Application.put_env(:dirmoon, OpenAI, Keyword.merge(original, overrides))
    on_exit(fn -> Application.put_env(:dirmoon, OpenAI, original) end)
  end

  defp stub_text(body, status) do
    Req.Test.stub(OpenAI, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("text/plain")
      |> Plug.Conn.send_resp(status, body)
    end)
  end

  defp stub_json(body, status \\ 200) do
    test_pid = self()

    Req.Test.stub(OpenAI, fn conn ->
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
end
