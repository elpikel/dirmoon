defmodule Dirmoon.PageSpeed.HTTPTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Dirmoon.PageSpeed.HTTP

  @api_key "test-pagespeed-key"
  @page "https://hotel-dla-psow-testowy.example/"

  test "a check asks for the page on a phone with the performance and accessibility categories and the key" do
    stub_json(lighthouse_body(%{}))

    HTTP.check(%{url: @page})

    assert_received {:request, %{method: "GET", path: "/pagespeedonline/v5/runPagespeed", params: params}}

    assert params == [
             {"url", @page},
             {"key", @api_key},
             {"strategy", "mobile"},
             {"category", "performance"},
             {"category", "accessibility"}
           ]
  end

  test "a check returns the score, the lab figures, the version and what they were read from in Google's answer" do
    stub_json(lighthouse_body(%{}))

    assert {:ok, %{result: result, raw: raw}} = HTTP.check(%{url: @page})

    assert raw == %{
             "loadingExperience" => %{"initial_url" => @page},
             "lighthouseResult" => %{
               "lighthouseVersion" => "13.0.1",
               "categories" => %{"performance" => %{"id" => "performance", "score" => 0.73}},
               "audits" => %{
                 "largest-contentful-paint" => %{"numericValue" => 3121.4, "scoreDisplayMode" => "numeric"},
                 "total-blocking-time" => %{"numericValue" => 244.6, "scoreDisplayMode" => "numeric"},
                 "cumulative-layout-shift" => %{"numericValue" => 0.087, "scoreDisplayMode" => "numeric"},
                 "viewport-insight" => %{"scoreDisplayMode" => "metricSavings", "score" => 1},
                 "meta-viewport" => %{"scoreDisplayMode" => "binary", "score" => 0},
                 "target-size" => %{"scoreDisplayMode" => "notApplicable", "score" => nil}
               }
             }
           }

    assert %{
             "performance_score" => 73,
             "largest_contentful_paint_ms" => 3121,
             "total_blocking_time_ms" => 245,
             "cumulative_layout_shift" => 0.087,
             "lighthouse_version" => "13.0.1"
           } = result
  end

  test "the raw answer keeps no screenshot, translation strings or check details" do
    screenshot = "data:image/jpeg;base64," <> String.duplicate("QUJD", 1_000)

    checks = %{
      "final-screenshot" => %{
        "id" => "final-screenshot",
        "score" => nil,
        "scoreDisplayMode" => "informative",
        "details" => %{"type" => "screenshot", "data" => screenshot}
      },
      "screenshot-thumbnails" => %{"id" => "screenshot-thumbnails", "details" => %{"items" => [%{"data" => screenshot}]}},
      "largest-contentful-paint" => %{
        "id" => "largest-contentful-paint",
        "score" => 0.4,
        "scoreDisplayMode" => "numeric",
        "numericValue" => 3121.4,
        "displayValue" => "3.1 s",
        "title" => "Largest Contentful Paint",
        "details" => %{"items" => [%{"node" => %{"snippet" => "<img>"}}]}
      }
    }

    %{"audits" => checks, "fullPageScreenshot" => %{"screenshot" => %{"data" => screenshot}}}
    |> lighthouse_body()
    |> Map.update!("lighthouseResult", &Map.put(&1, "i18n", %{"rendererFormattedStrings" => %{"a" => "b"}}))
    |> Map.put("originLoadingExperience", %{"id" => "https://hotel-dla-psow-testowy.example"})
    |> stub_json()

    assert {:ok, %{raw: raw}} = HTTP.check(%{url: @page})

    refute inspect(raw, limit: :infinity, printable_limit: :infinity) =~ "base64"
    refute Map.has_key?(raw["lighthouseResult"], "fullPageScreenshot")
    refute Map.has_key?(raw["lighthouseResult"], "i18n")
    assert raw["originLoadingExperience"] == %{"id" => "https://hotel-dla-psow-testowy.example"}

    assert raw["lighthouseResult"]["audits"] == %{
             "final-screenshot" => %{"id" => "final-screenshot", "score" => nil, "scoreDisplayMode" => "informative"},
             "screenshot-thumbnails" => %{"id" => "screenshot-thumbnails"},
             "largest-contentful-paint" => %{
               "id" => "largest-contentful-paint",
               "score" => 0.4,
               "scoreDisplayMode" => "numeric",
               "numericValue" => 3121.4,
               "displayValue" => "3.1 s"
             }
           }
  end

  test "an answer whose checks are not a map keeps none in its raw answer" do
    stub_json(%{"lighthouseResult" => %{"audits" => "odd"}})
    assert {:ok, %{raw: %{"lighthouseResult" => %{"audits" => %{}}}}} = HTTP.check(%{url: @page})

    stub_json(%{"lighthouseResult" => %{"audits" => %{"meta-viewport" => "odd"}}})
    assert {:ok, %{raw: %{"lighthouseResult" => %{"audits" => %{"meta-viewport" => %{}}}}}} = HTTP.check(%{url: @page})
  end

  test "the phone checks present are passed or failed, and not applicable ones have no verdict" do
    stub_json(lighthouse_body(%{}))

    assert {:ok, %{result: %{"phone_checks" => phone_checks}}} = HTTP.check(%{url: @page})

    assert phone_checks == [
             %{"id" => "viewport-insight", "passed" => true},
             %{"id" => "meta-viewport", "passed" => false},
             %{"id" => "target-size", "passed" => nil}
           ]
  end

  test "phone checks missing from the answer are left out, and a check without a score has no verdict" do
    checks = %{"meta-viewport" => %{"id" => "meta-viewport", "scoreDisplayMode" => "binary", "score" => nil}}
    stub_json(lighthouse_body(%{"audits" => checks}))

    assert {:ok, %{result: %{"phone_checks" => [%{"id" => "meta-viewport", "passed" => nil}]}}} =
             HTTP.check(%{url: @page})
  end

  test "an answer without scores, figures, checks or visitor data gives an empty result instead of failing" do
    stub_json(%{"lighthouseResult" => %{"categories" => "odd", "audits" => "odd"}})

    assert {:ok, %{result: result}} = HTTP.check(%{url: @page})

    assert result == %{
             "performance_score" => nil,
             "largest_contentful_paint_ms" => nil,
             "total_blocking_time_ms" => nil,
             "cumulative_layout_shift" => nil,
             "lighthouse_version" => nil,
             "field" => %{},
             "phone_checks" => []
           }
  end

  test "visitor figures come from the page's own data with their category" do
    stub_json(
      Map.put(lighthouse_body(%{}), "loadingExperience", %{
        "metrics" => %{
          "LARGEST_CONTENTFUL_PAINT_MS" => %{"percentile" => 2900, "category" => "AVERAGE"},
          "INTERACTION_TO_NEXT_PAINT" => %{"percentile" => 180, "category" => "FAST"},
          "CUMULATIVE_LAYOUT_SHIFT_SCORE" => %{"percentile" => 12}
        }
      })
    )

    assert {:ok, %{result: %{"field" => field}}} = HTTP.check(%{url: @page})

    assert field == %{
             "largest_contentful_paint" => %{"percentile" => 2900, "category" => "AVERAGE", "scope" => "page"},
             "interaction_to_next_paint" => %{"percentile" => 180, "category" => "FAST", "scope" => "page"},
             "cumulative_layout_shift" => %{"percentile" => 12, "category" => nil, "scope" => "page"}
           }
  end

  test "visitor figures Google fell back to for the whole site, or that only the site has, are marked as the site's" do
    %{}
    |> lighthouse_body()
    |> Map.put("loadingExperience", %{
      "origin_fallback" => true,
      "metrics" => %{"LARGEST_CONTENTFUL_PAINT_MS" => %{"percentile" => 4100, "category" => "SLOW"}}
    })
    |> Map.put("originLoadingExperience", %{
      "metrics" => %{"INTERACTION_TO_NEXT_PAINT" => %{"percentile" => 520, "category" => "SLOW"}}
    })
    |> stub_json()

    assert {:ok, %{result: %{"field" => field}}} = HTTP.check(%{url: @page})

    assert field == %{
             "largest_contentful_paint" => %{"percentile" => 4100, "category" => "SLOW", "scope" => "origin"},
             "interaction_to_next_paint" => %{"percentile" => 520, "category" => "SLOW", "scope" => "origin"}
           }
  end

  test "a page Google could not load, reported in a 200 answer, is page unreachable" do
    stub_json(lighthouse_body(%{"runtimeError" => %{"code" => "NO_FCP", "message" => "The page did not paint"}}))

    assert HTTP.check(%{url: @page}) == {:error, :page_unreachable}
  end

  test "a runtime error saying there is no error keeps the result" do
    stub_json(lighthouse_body(%{"runtimeError" => %{"code" => "NO_ERROR"}}))

    assert {:ok, %{result: %{"performance_score" => 73}}} = HTTP.check(%{url: @page})
  end

  test "a page Google could not load, reported as an error, is page unreachable" do
    for status <- [400, 500] do
      stub_json(
        google_error(%{
          code: status,
          status: "INVALID_ARGUMENT",
          message: "Lighthouse returned error: FAILED_DOCUMENT_REQUEST. Lighthouse was unable to load the page."
        }),
        status
      )

      assert HTTP.check(%{url: @page}) == {:error, :page_unreachable}
    end
  end

  test "an exhausted quota is quota exceeded" do
    stub_json(google_error(%{code: 429, status: "RESOURCE_EXHAUSTED", message: "Quota exceeded for quota metric"}), 429)
    assert HTTP.check(%{url: @page}) == {:error, :page_speed_quota_exceeded}

    stub_json(google_error(%{code: 400, status: "RESOURCE_EXHAUSTED", message: "Quota exceeded"}), 400)
    assert HTTP.check(%{url: @page}) == {:error, :page_speed_quota_exceeded}
  end

  test "a refused key or an API not enabled for it is key rejected" do
    for {http_status, status, message} <- [
          {400, "INVALID_ARGUMENT", "API key not valid. Please pass a valid API key."},
          {403, "PERMISSION_DENIED", "PageSpeed Insights API has not been used in project 1 before or it is disabled."},
          {400, "PERMISSION_DENIED", "Requests from this referrer are blocked."},
          {401, "UNAUTHENTICATED", "Request is missing required authentication credential."}
        ] do
      stub_json(google_error(%{code: http_status, status: status, message: message}), http_status)

      assert HTTP.check(%{url: @page}) == {:error, :page_speed_key_rejected}
    end
  end

  test "any other error is failed with Google's status and message" do
    stub_json(google_error(%{code: 500, status: "INTERNAL", message: "Something went wrong."}), 500)
    assert HTTP.check(%{url: @page}) == {:error, {:page_speed_failed, "PageSpeed: HTTP 500: Something went wrong."}}

    stub_json(%{"error" => %{"code" => 503}}, 503)
    assert HTTP.check(%{url: @page}) == {:error, {:page_speed_failed, "PageSpeed: HTTP 503: "}}
  end

  test "an answer that is not Google's error or result is failed with its HTTP status" do
    stub_json(%{"kind" => "pagespeedonline#result"})
    assert HTTP.check(%{url: @page}) == {:error, {:page_speed_failed, "PageSpeed: answer without a Lighthouse result"}}

    Req.Test.stub(HTTP, &Plug.Conn.send_resp(&1, 502, "Bad Gateway"))
    assert HTTP.check(%{url: @page}) == {:error, {:page_speed_failed, "PageSpeed: HTTP 502"}}
  end

  test "a transport failure is failed with its reason, without a retry" do
    test_pid = self()

    Req.Test.stub(HTTP, fn conn ->
      send(test_pid, :requested)
      Req.Test.transport_error(conn, :timeout)
    end)

    assert HTTP.check(%{url: @page}) == {:error, {:page_speed_failed, "PageSpeed: timeout"}}
    assert_received :requested
    refute_received :requested
  end

  test "the key never appears in the raw answer, an error or a log" do
    stub_json(lighthouse_body(%{}))

    success_log =
      capture_log(fn ->
        assert {:ok, %{result: result, raw: raw}} = HTTP.check(%{url: @page})
        refute inspect({result, raw}) =~ @api_key
      end)

    stub_json(google_error(%{code: 500, status: "INTERNAL", message: "Bad request for key=#{@api_key}"}), 500)

    error_log =
      capture_log(fn ->
        assert {:error, {:page_speed_failed, message}} = HTTP.check(%{url: @page})
        assert message == "PageSpeed: HTTP 500: Bad request for key=[key]"
      end)

    refute success_log =~ @api_key
    refute error_log =~ @api_key
  end

  defp stub_json(body, status \\ 200) do
    test_pid = self()

    Req.Test.stub(HTTP, fn conn ->
      send(test_pid, {
        :request,
        %{
          method: conn.method,
          path: conn.request_path,
          params: conn.query_string |> URI.query_decoder() |> Enum.to_list()
        }
      })

      conn
      |> Plug.Conn.put_status(status)
      |> Req.Test.json(body)
    end)
  end

  defp google_error(%{code: code, status: status, message: message}) do
    %{
      "error" => %{
        "code" => code,
        "message" => message,
        "status" => status,
        "errors" => [%{"message" => message, "domain" => "global", "reason" => "badRequest"}]
      }
    }
  end

  defp lighthouse_body(lighthouse_fields) do
    %{
      "captchaResult" => "CAPTCHA_NOT_NEEDED",
      "kind" => "pagespeedonline#result",
      "id" => @page,
      "loadingExperience" => %{"initial_url" => @page},
      "lighthouseResult" =>
        Map.merge(
          %{
            "requestedUrl" => @page,
            "finalUrl" => @page,
            "lighthouseVersion" => "13.0.1",
            "categories" => %{"performance" => %{"id" => "performance", "score" => 0.73}},
            "audits" => %{
              "largest-contentful-paint" => %{"numericValue" => 3121.4, "scoreDisplayMode" => "numeric"},
              "total-blocking-time" => %{"numericValue" => 244.6, "scoreDisplayMode" => "numeric"},
              "cumulative-layout-shift" => %{"numericValue" => 0.087, "scoreDisplayMode" => "numeric"},
              "viewport-insight" => %{"scoreDisplayMode" => "metricSavings", "score" => 1},
              "meta-viewport" => %{"scoreDisplayMode" => "binary", "score" => 0},
              "target-size" => %{"scoreDisplayMode" => "notApplicable", "score" => nil}
            }
          },
          lighthouse_fields
        )
    }
  end
end
