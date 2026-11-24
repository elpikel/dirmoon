defmodule Dirmoon.SearchConsole.Client.GoogleTest do
  use ExUnit.Case, async: false

  alias Dirmoon.SearchConsole.Client.Google

  @client_id "test-google-client-id"
  @client_secret "test-google-client-secret"
  @redirect_uri "http://localhost:4002/app/search-console/callback"

  test "the authorization url asks Google for offline, read-only Search Console access and the email" do
    assert {:ok, url} = Google.authorize_url(%{state: "losowy-stan", redirect_uri: @redirect_uri})

    uri = URI.parse(url)
    assert "#{uri.scheme}://#{uri.host}#{uri.path}" == "https://accounts.google.com/o/oauth2/v2/auth"

    assert URI.decode_query(uri.query) == %{
             "client_id" => @client_id,
             "redirect_uri" => @redirect_uri,
             "response_type" => "code",
             "scope" => "openid email https://www.googleapis.com/auth/webmasters.readonly",
             "access_type" => "offline",
             "prompt" => "consent",
             "state" => "losowy-stan"
           }

    refute url =~ @client_secret
  end

  test "exchanging a code returns the refresh token, the access token and the email from the id token" do
    stub_json(exchange_body())

    assert Google.exchange_code(%{code: "4/kod-google", redirect_uri: @redirect_uri}) ==
             {:ok,
              %{
                refresh_token: "1//0gEXAMPLE-refresh",
                access_token: "ya29.a0AfB_byC-EXAMPLE",
                email: "jsmith@example.com"
              }}
  end

  test "exchanging a code posts the code, client credentials, redirect uri and grant type as a form" do
    stub_json(exchange_body())

    Google.exchange_code(%{code: "4/kod-google", redirect_uri: @redirect_uri})

    assert_received {:request, %{method: "POST", host: "oauth2.googleapis.com", path: "/token"} = request}
    assert request.content_type =~ "application/x-www-form-urlencoded"

    assert URI.decode_query(request.body) == %{
             "code" => "4/kod-google",
             "client_id" => @client_id,
             "client_secret" => @client_secret,
             "redirect_uri" => @redirect_uri,
             "grant_type" => "authorization_code"
           }
  end

  test "an exchange without a refresh token fails" do
    stub_json(Map.delete(exchange_body(), "refresh_token"))

    assert Google.exchange_code(%{code: "4/kod", redirect_uri: @redirect_uri}) == {:error, :no_refresh_token}
  end

  test "an exchange answered without an access token fails" do
    stub_json(Map.delete(exchange_body(), "access_token"))

    assert Google.exchange_code(%{code: "4/kod", redirect_uri: @redirect_uri}) ==
             {:error, "Google OAuth: no access token"}
  end

  test "a refresh answered without an access token fails" do
    stub_json(%{"expires_in" => 3599, "token_type" => "Bearer"})

    assert Google.refresh_access_token(%{refresh_token: "1//0gEXAMPLE-refresh"}) ==
             {:error, "Google OAuth: no access token"}
  end

  test "an exchange where the user unticked Search Console access fails" do
    stub_json(Map.put(exchange_body(), "scope", "openid https://www.googleapis.com/auth/userinfo.email"))

    assert Google.exchange_code(%{code: "4/kod", redirect_uri: @redirect_uri}) ==
             {:error, :search_console_scope_not_granted}
  end

  test "an exchange without an email in the id token fails" do
    stub_json(Map.put(exchange_body(), "id_token", id_token(%{"sub" => "110169484474386276334"})))

    assert Google.exchange_code(%{code: "4/kod", redirect_uri: @redirect_uri}) == {:error, :no_google_email}
  end

  test "a used or invalid code is reported as an invalid grant" do
    stub_json(%{"error" => "invalid_grant", "error_description" => "Bad Request"}, 400)

    assert Google.exchange_code(%{code: "4/zuzyty", redirect_uri: @redirect_uri}) == {:error, :invalid_grant}
  end

  test "other OAuth errors name the error code but never the client secret or the code" do
    stub_json(%{"error" => "invalid_client", "error_description" => "The OAuth client was not found."}, 401)

    assert {:error, reason} = Google.exchange_code(%{code: "4/tajny-kod", redirect_uri: @redirect_uri})
    assert reason == "Google OAuth: invalid_client"
    refute reason =~ @client_secret
    refute reason =~ "tajny-kod"
  end

  test "a transport failure is reported without credentials" do
    Req.Test.stub(Google, &Req.Test.transport_error(&1, :econnrefused))

    assert {:error, reason} = Google.refresh_access_token(%{refresh_token: "1//tajny-refresh"})
    refute inspect(reason) =~ @client_secret
    refute inspect(reason) =~ "tajny-refresh"
  end

  test "refreshing returns a new access token and its lifetime" do
    stub_json(%{
      "access_token" => "ya29.a0NEW-EXAMPLE",
      "expires_in" => 3599,
      "scope" =>
        "https://www.googleapis.com/auth/webmasters.readonly openid https://www.googleapis.com/auth/userinfo.email",
      "token_type" => "Bearer"
    })

    assert Google.refresh_access_token(%{refresh_token: "1//0gEXAMPLE-refresh"}) ==
             {:ok, %{access_token: "ya29.a0NEW-EXAMPLE", expires_in: 3599}}

    assert_received {:request, %{method: "POST", path: "/token", body: body}}

    assert URI.decode_query(body) == %{
             "client_id" => @client_id,
             "client_secret" => @client_secret,
             "refresh_token" => "1//0gEXAMPLE-refresh",
             "grant_type" => "refresh_token"
           }
  end

  test "a revoked or expired refresh token is reported as an invalid grant" do
    stub_json(%{"error" => "invalid_grant", "error_description" => "Token has been expired or revoked."}, 400)

    assert Google.refresh_access_token(%{refresh_token: "1//odwolany"}) == {:error, :invalid_grant}
  end

  test "a query posts the date range, the query dimension and the row limit to the encoded domain property" do
    stub_json(query_body())

    Google.query(query_request())

    assert_received {:request, request}
    assert request.method == "POST"
    assert request.host == "searchconsole.googleapis.com"
    assert request.path == "/webmasters/v3/sites/sc-domain%3Aexample.pl/searchAnalytics/query"
    assert request.authorization == "Bearer ya29.access-token"

    assert Jason.decode!(request.body) == %{
             "startDate" => "2026-08-24",
             "endDate" => "2026-11-21",
             "dimensions" => ["query"],
             "type" => "web",
             "rowLimit" => 25_000
           }
  end

  test "a query returns each row's query, clicks, impressions, ctr and position, and the raw response" do
    stub_json(query_body())

    assert {:ok, %{rows: rows, raw: raw}} = Google.query(query_request())

    assert rows == [
             %{query: "buty do biegania", clicks: 42, impressions: 1310, ctr: 0.03206106870229008, position: 7.4},
             %{query: "buty trailowe", clicks: 5, impressions: 220, ctr: 0.022727272727272728, position: 12.1}
           ]

    assert raw == query_body()
  end

  test "a query without data returns no rows" do
    stub_json(%{"responseAggregationType" => "byProperty"})

    assert {:ok, %{rows: [], raw: %{"responseAggregationType" => "byProperty"}}} = Google.query(query_request())
  end

  test "a property the Google user cannot access is reported as forbidden" do
    stub_json(forbidden_body(), 403)

    assert Google.query(query_request()) == {:error, :forbidden}
  end

  test "an expired access token is reported as unauthorized" do
    stub_json(%{"error" => %{"code" => 401, "message" => "Request had invalid authentication credentials."}}, 401)

    assert Google.query(query_request()) == {:error, :unauthorized}
  end

  test "other query errors carry Google's message but never the access token" do
    stub_json(%{"error" => %{"code" => 400, "message" => "Invalid value at 'start_date'."}}, 400)

    assert {:error, reason} = Google.query(query_request())
    assert reason == "Google Search Console: Invalid value at 'start_date'."
    refute reason =~ "ya29.access-token"
  end

  test "Google credentials in env vars switch to the Google client with those credentials" do
    previous_env = Map.new(["GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET"], &{&1, System.get_env(&1)})
    System.put_env("GOOGLE_CLIENT_ID", "env-client-id")
    System.put_env("GOOGLE_CLIENT_SECRET", "env-client-secret")

    config =
      try do
        Config.Reader.read!("config/runtime.exs", env: :dev)
      after
        Enum.each(previous_env, &restore_env/1)
      end

    assert get_in(config, [:dirmoon, :search_console_adapter]) == Google
    assert get_in(config, [:dirmoon, Google, :client_id]) == "env-client-id"
    assert get_in(config, [:dirmoon, Google, :client_secret]) == "env-client-secret"
  end

  defp query_request do
    %{
      access_token: "ya29.access-token",
      site_url: "sc-domain:example.pl",
      start_date: ~D[2026-08-24],
      end_date: ~D[2026-11-21],
      row_limit: 25_000
    }
  end

  defp stub_json(body, status \\ 200) do
    test_pid = self()

    Req.Test.stub(Google, fn conn ->
      {:ok, request_body, conn} = Plug.Conn.read_body(conn)

      send(test_pid, {
        :request,
        %{
          method: conn.method,
          host: conn.host,
          path: conn.request_path,
          body: request_body,
          content_type: conn |> Plug.Conn.get_req_header("content-type") |> List.first(),
          authorization: conn |> Plug.Conn.get_req_header("authorization") |> List.first()
        }
      })

      conn
      |> Plug.Conn.put_status(status)
      |> Req.Test.json(body)
    end)
  end

  defp exchange_body do
    %{
      "access_token" => "ya29.a0AfB_byC-EXAMPLE",
      "expires_in" => 3599,
      "refresh_token" => "1//0gEXAMPLE-refresh",
      "scope" =>
        "openid https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/webmasters.readonly",
      "token_type" => "Bearer",
      "id_token" =>
        id_token(%{
          "iss" => "https://accounts.google.com",
          "aud" => "#{@client_id}.apps.googleusercontent.com",
          "sub" => "110169484474386276334",
          "email" => "jsmith@example.com",
          "email_verified" => true
        })
    }
  end

  defp id_token(claims) do
    [%{"alg" => "RS256", "kid" => "1"}, claims]
    |> Enum.map(&(&1 |> Jason.encode!() |> Base.url_encode64(padding: false)))
    |> Enum.concat(["SIG"])
    |> Enum.join(".")
  end

  defp query_body do
    %{
      "rows" => [
        %{
          "keys" => ["buty do biegania"],
          "clicks" => 42,
          "impressions" => 1310,
          "ctr" => 0.03206106870229008,
          "position" => 7.4
        },
        %{
          "keys" => ["buty trailowe"],
          "clicks" => 5,
          "impressions" => 220,
          "ctr" => 0.022727272727272728,
          "position" => 12.1
        }
      ],
      "responseAggregationType" => "byProperty"
    }
  end

  defp forbidden_body do
    message =
      "User does not have sufficient permission for site 'sc-domain:example.pl'. See also: https://support.google.com/webmasters/answer/2451999."

    %{
      "error" => %{
        "code" => 403,
        "message" => message,
        "errors" => [%{"message" => message, "domain" => "global", "reason" => "forbidden"}],
        "status" => "PERMISSION_DENIED"
      }
    }
  end

  defp restore_env({name, nil}), do: System.delete_env(name)
  defp restore_env({name, value}), do: System.put_env(name, value)
end
