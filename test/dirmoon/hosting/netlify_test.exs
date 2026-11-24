defmodule Dirmoon.Hosting.NetlifyTest do
  use ExUnit.Case, async: true

  alias Dirmoon.Hosting.Netlify

  @token "test-netlify-token"
  @site_id "3970e0fe-8564-4903-9a55-c5f8de49fb8b"
  @deploy_id "6740f1a2b3c4d50008e1f2a3"
  @live_url "https://dirmoon-buty-do-biegania.netlify.app"

  test "creating a site posts its name and answers the site id" do
    respond_site_created()

    assert Netlify.create_site(%{site_name: "dirmoon-buty-do-biegania"}) == {:ok, %{site_id: @site_id}}

    assert_received {:request, %{method: "POST", path: "/api/v1/sites", body: site_body, authorization: authorization}}
    assert Jason.decode!(site_body) == %{"name" => "dirmoon-buty-do-biegania"}
    assert authorization == "Bearer " <> @token
  end

  test "a site name Netlify reports taken is tried once more with a suffix" do
    expect_response(fn _conn -> {422, %{"errors" => %{"subdomain" => ["must be unique"]}}} end)
    respond_site_created()

    assert {:ok, %{site_id: @site_id}} = Netlify.create_site(%{site_name: "dirmoon-buty-do-biegania"})

    assert_received {:request, %{method: "POST", path: "/api/v1/sites", body: first_body}}
    assert_received {:request, %{method: "POST", path: "/api/v1/sites", body: second_body}}
    assert Jason.decode!(first_body) == %{"name" => "dirmoon-buty-do-biegania"}
    assert %{"name" => "dirmoon-buty-do-biegania-" <> suffix} = Jason.decode!(second_body)
    assert suffix =~ ~r/\A[a-z0-9]{4}\z/
  end

  test "the site name is cut down to lowercase letters, digits and hyphens" do
    respond_site_created()

    {:ok, _site} = Netlify.create_site(%{site_name: "Dirmoon Buty_do Biegania!"})

    assert_received {:request, %{method: "POST", path: "/api/v1/sites", body: body}}
    assert Jason.decode!(body) == %{"name" => "dirmoon-buty-do-biegania"}
  end

  test "a site answer without an id fails" do
    expect_response(fn _conn -> {201, Map.delete(site_body(), "id")} end)

    assert Netlify.create_site(%{site_name: "dirmoon-strona"}) == {:error, "Netlify: odpowiedź bez id strony"}
  end

  test "deploying to a site sends the zip, polls until ready and answers the https url" do
    respond_deploy_created("uploaded")
    respond_deploy_polled("ready")

    assert Netlify.deploy(%{site_id: @site_id, html: html()}) == {:ok, %{url: @live_url}}

    assert_received {:request, %{method: "POST", path: "/api/v1/sites/" <> @site_id <> "/deploys"}}
    assert_received {:request, %{method: "GET", path: "/api/v1/deploys/" <> @deploy_id}}
    refute_received {:request, %{path: "/api/v1/sites"}}
  end

  test "the deploy is a zip whose only entry index.html is the page, sent with the bearer token" do
    respond_deploy_created("ready")

    {:ok, _deployed} = Netlify.deploy(%{site_id: @site_id, html: html()})

    assert_received {:request,
                     %{
                       method: "POST",
                       path: "/api/v1/sites/" <> @site_id <> "/deploys",
                       content_type: "application/zip",
                       authorization: deploy_authorization,
                       body: zip
                     }}

    assert deploy_authorization == "Bearer " <> @token
    assert {:ok, [{~c"index.html", unzipped_html}]} = :zip.unzip(zip, [:memory])
    assert unzipped_html == html()
  end

  test "a deploy Netlify fails to process answers its error message" do
    respond_deploy_created("uploaded")
    respond_deploy_polled("error", %{"error_message" => "Failed to process deploy"})

    assert Netlify.deploy(%{site_id: @site_id, html: html()}) == {:error, "Netlify: Failed to process deploy"}

    assert_received {:request, %{method: "POST", path: "/api/v1/sites/" <> @site_id <> "/deploys"}}
    assert_received {:request, %{method: "GET", path: "/api/v1/deploys/" <> @deploy_id}}
  end

  test "a deploy still processing after every poll fails as not finished in time" do
    respond_deploy_created("uploaded")
    respond_deploy_polled("processing", %{}, 3)

    assert Netlify.deploy(%{site_id: @site_id, html: html()}) == {:error, "Netlify: deploy nie zakończył się na czas"}

    assert_received {:request, %{method: "GET", path: "/api/v1/deploys/" <> @deploy_id}}
    assert_received {:request, %{method: "GET", path: "/api/v1/deploys/" <> @deploy_id}}
    assert_received {:request, %{method: "GET", path: "/api/v1/deploys/" <> @deploy_id}}
  end

  test "a rejected token fails as an invalid token" do
    expect_response(fn _conn -> {401, %{"code" => 401, "message" => "Access Denied: " <> @token}} end)

    assert {:error, "Netlify: nieprawidłowy token" = message} = Netlify.create_site(%{site_name: "dirmoon-strona"})

    refute message =~ @token
  end

  test "another failed answer carries Netlify's message, with the token cut out" do
    expect_response(fn _conn -> {404, %{"code" => 404, "message" => "Not Found for " <> @token}} end)

    assert {:error, message} = Netlify.deploy(%{site_id: @site_id, html: html()})

    assert message =~ "Netlify: Not Found"
    refute message =~ @token
  end

  test "a failed answer without a message carries the HTTP status" do
    expect_response(fn _conn -> {500, ""} end)

    assert Netlify.deploy(%{site_id: @site_id, html: html()}) == {:error, "Netlify: HTTP 500"}
  end

  test "a connection failure is an error without the token" do
    Req.Test.expect(Netlify, &Req.Test.transport_error(&1, :econnrefused))

    assert {:error, "Netlify: " <> message} = Netlify.deploy(%{site_id: @site_id, html: html()})

    refute message =~ @token
  end

  test "a connection failure while creating a site carries the transport reason" do
    Req.Test.expect(Netlify, &Req.Test.transport_error(&1, :timeout))

    assert Netlify.create_site(%{site_name: "dirmoon-strona"}) == {:error, "Netlify: timeout"}
  end

  test "a site name with no usable characters falls back to dirmoon" do
    respond_site_created()

    {:ok, _site} = Netlify.create_site(%{site_name: "!!! ???"})

    assert_received {:request, %{method: "POST", path: "/api/v1/sites", body: body}}
    assert Jason.decode!(body) == %{"name" => "dirmoon"}
  end

  test "a 422 answer that does not mention the subdomain is not retried" do
    expect_response(fn _conn -> {422, %{"errors" => %{"name" => ["is invalid"]}}} end)

    assert Netlify.create_site(%{site_name: "dirmoon-strona"}) == {:error, "Netlify: HTTP 422"}

    assert_received {:request, %{method: "POST", path: "/api/v1/sites"}}
    refute_received {:request, _second_request}
  end

  test "a 422 plain-text answer mentioning the subdomain is tried once more with a suffix" do
    expect_response(fn _conn -> {422, "subdomain must be unique"} end)
    respond_site_created()

    assert {:ok, %{site_id: @site_id}} = Netlify.create_site(%{site_name: "dirmoon-strona"})

    assert_received {:request, %{method: "POST", path: "/api/v1/sites"}}
    assert_received {:request, %{method: "POST", path: "/api/v1/sites", body: second_body}}
    assert %{"name" => "dirmoon-strona-" <> _suffix} = Jason.decode!(second_body)
  end

  test "a 422 answer whose body is a JSON list is not retried" do
    expect_response(fn _conn -> {422, ["subdomain"]} end)

    assert Netlify.create_site(%{site_name: "dirmoon-strona"}) == {:error, "Netlify: HTTP 422"}

    assert_received {:request, %{method: "POST", path: "/api/v1/sites"}}
    refute_received {:request, _second_request}
  end

  test "a deploy answer without an id fails" do
    expect_response(fn _conn -> {200, Map.delete(deploy_body("uploaded"), "id")} end)

    assert Netlify.deploy(%{site_id: @site_id, html: html()}) == {:error, "Netlify: odpowiedź bez id deployu"}
  end

  test "a rejected deploy without an error message fails with a generic message" do
    respond_deploy_created("uploaded")
    respond_deploy_polled("rejected")

    assert Netlify.deploy(%{site_id: @site_id, html: html()}) == {:error, "Netlify: deploy zakończył się błędem"}
  end

  test "a poll answer that is not a deploy object fails" do
    respond_deploy_created("uploaded")
    expect_response(fn _conn -> {200, "processing"} end)

    assert Netlify.deploy(%{site_id: @site_id, html: html()}) ==
             {:error, "Netlify: niepoprawna odpowiedź o stanie deployu"}
  end

  test "a failed poll answer carries the HTTP status" do
    respond_deploy_created("uploaded")
    expect_response(fn _conn -> {502, ""} end)

    assert Netlify.deploy(%{site_id: @site_id, html: html()}) == {:error, "Netlify: HTTP 502"}
  end

  test "a ready deploy without any url fails" do
    expect_response(fn _conn -> {200, Map.merge(deploy_body("ready"), %{"ssl_url" => nil, "url" => ""})} end)

    assert Netlify.deploy(%{site_id: @site_id, html: html()}) == {:error, "Netlify: odpowiedź bez adresu strony"}
  end

  test "a ready deploy without an https url answers its plain url" do
    expect_response(fn _conn -> {200, Map.put(deploy_body("ready"), "ssl_url", nil)} end)

    assert Netlify.deploy(%{site_id: @site_id, html: html()}) ==
             {:ok, %{url: "http://dirmoon-buty-do-biegania.netlify.app"}}
  end

  defp html, do: "<!DOCTYPE html><html><body><h1>Buty do biegania</h1></body></html>"

  defp respond_site_created, do: expect_response(fn _conn -> {201, site_body()} end)

  defp respond_deploy_created(state), do: expect_response(fn _conn -> {200, deploy_body(state)} end)

  defp respond_deploy_polled(state, extra \\ %{}, times \\ 1) do
    expect_response(times, fn _conn -> {200, Map.merge(deploy_body(state), extra)} end)
  end

  defp expect_response(times \\ 1, respond) do
    test_pid = self()

    Req.Test.expect(Netlify, times, fn conn ->
      {:ok, request_body, conn} = Plug.Conn.read_body(conn)

      send(test_pid, {
        :request,
        %{
          method: conn.method,
          path: conn.request_path,
          body: request_body,
          content_type: conn |> Plug.Conn.get_req_header("content-type") |> List.first(),
          authorization: conn |> Plug.Conn.get_req_header("authorization") |> List.first()
        }
      })

      case respond.(conn) do
        {status, body} when is_map(body) or is_list(body) -> conn |> Plug.Conn.put_status(status) |> Req.Test.json(body)
        {status, body} -> Plug.Conn.send_resp(conn, status, body)
      end
    end)
  end

  defp site_body do
    %{
      "id" => @site_id,
      "state" => "current",
      "name" => "dirmoon-buty-do-biegania",
      "custom_domain" => nil,
      "url" => "http://dirmoon-buty-do-biegania.netlify.app",
      "ssl_url" => @live_url,
      "admin_url" => "https://app.netlify.com/sites/dirmoon-buty-do-biegania",
      "deploy_url" => "http://main--dirmoon-buty-do-biegania.netlify.app",
      "created_at" => "2026-11-24T10:00:00.000Z",
      "updated_at" => "2026-11-24T10:00:00.000Z",
      "published_deploy" => nil
    }
  end

  defp deploy_body(state) do
    %{
      "id" => @deploy_id,
      "site_id" => @site_id,
      "state" => state,
      "name" => "dirmoon-buty-do-biegania",
      "url" => "http://dirmoon-buty-do-biegania.netlify.app",
      "ssl_url" => @live_url,
      "admin_url" => "https://app.netlify.com/sites/dirmoon-buty-do-biegania",
      "deploy_url" => "http://#{@deploy_id}--dirmoon-buty-do-biegania.netlify.app",
      "deploy_ssl_url" => "https://#{@deploy_id}--dirmoon-buty-do-biegania.netlify.app",
      "error_message" => nil,
      "required" => [],
      "required_functions" => [],
      "context" => "production",
      "created_at" => "2026-11-24T10:01:00.000Z",
      "updated_at" => "2026-11-24T10:01:00.000Z",
      "published_at" => nil
    }
  end
end
