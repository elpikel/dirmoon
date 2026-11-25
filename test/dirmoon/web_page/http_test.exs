defmodule Dirmoon.WebPage.HTTPTest do
  use ExUnit.Case, async: true

  alias Dirmoon.WebPage.HTTP

  test "an HTML page is read with a GET and a generic User-Agent and comes back as visible text" do
    test_pid = self()

    Req.Test.stub(HTTP, fn conn ->
      send(
        test_pid,
        {:request, %{method: conn.method, host: conn.host, path: conn.request_path, headers: conn.req_headers}}
      )

      html(conn, "<html><body><h1>Cennik</h1><p>Doba 80&nbsp;zł</p></body></html>")
    end)

    assert {:ok, %{text: "Cennik Doba 80 zł", url: "https://hotel-testowy.example/cennik"}} =
             HTTP.fetch_text("https://hotel-testowy.example/cennik")

    assert_received {:request, %{method: "GET", host: "hotel-testowy.example", path: "/cennik", headers: headers}}
    assert {"user-agent", "Mozilla/5.0 (compatible; PageReader/1.0)"} in headers
    refute Enum.any?(headers, fn {name, _value} -> name in ["cookie", "authorization"] end)
  end

  test "a redirect is followed and the address finally read is returned" do
    Req.Test.stub(HTTP, fn
      %Plug.Conn{request_path: "/"} = conn -> redirect(conn, "/oferta")
      %Plug.Conn{request_path: "/oferta"} = conn -> html(conn, "<p>Oferta</p>")
    end)

    assert {:ok, %{text: "Oferta", url: "https://hotel-testowy.example/oferta"}} =
             HTTP.fetch_text("https://hotel-testowy.example/")
  end

  test "a redirect to a private address is refused without reading it" do
    test_pid = self()

    Req.Test.stub(HTTP, fn conn ->
      send(test_pid, {:requested, conn.host})
      redirect(conn, "http://169.254.169.254/latest/meta-data/")
    end)

    assert {:error, "an address in a private network"} = HTTP.fetch_text("https://hotel-testowy.example/")
    assert_received {:requested, "hotel-testowy.example"}
    refute_received {:requested, "169.254.169.254"}
  end

  test "more than three redirects give up" do
    Req.Test.stub(HTTP, fn conn -> redirect(conn, conn.request_path <> "x") end)

    assert {:error, "too many redirects"} = HTTP.fetch_text("https://hotel-testowy.example/")
  end

  test "a redirect without an address is an error" do
    Req.Test.stub(HTTP, fn conn -> Plug.Conn.send_resp(conn, 302, "") end)

    assert {:error, "redirect without an address"} = HTTP.fetch_text("https://hotel-testowy.example/")
  end

  test "an answer that is not HTML or text is not read" do
    Req.Test.stub(HTTP, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/pdf")
      |> Plug.Conn.send_resp(200, "%PDF-1.7 Doba 80 zł")
    end)

    assert {:error, "not an HTML page"} = HTTP.fetch_text("https://hotel-testowy.example/cennik.pdf")
  end

  test "a plain-text page is read" do
    Req.Test.stub(HTTP, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("text/plain")
      |> Plug.Conn.send_resp(200, "Doba 80 zł")
    end)

    assert {:ok, %{text: "Doba 80 zł"}} = HTTP.fetch_text("https://hotel-testowy.example/cennik.txt")
  end

  test "an error status is an error" do
    Req.Test.stub(HTTP, fn conn ->
      conn |> Plug.Conn.put_resp_content_type("text/html") |> Plug.Conn.send_resp(404, "")
    end)

    assert {:error, "HTTP 404"} = HTTP.fetch_text("https://hotel-testowy.example/brak")
  end

  test "a connection failure is an error" do
    Req.Test.stub(HTTP, &Req.Test.transport_error(&1, :econnrefused))

    assert {:error, message} = HTTP.fetch_text("https://hotel-testowy.example/")
    assert message =~ "connection refused"
  end

  test "an address that may not be read is refused without a request" do
    assert {:error, "a local address"} = HTTP.fetch_text("http://localhost:4000/")
    assert {:error, "the address is not an http or https page"} = HTTP.fetch_text("file:///etc/passwd")
  end

  test "only the first two megabytes of a page are downloaded" do
    Req.Test.stub(HTTP, fn conn ->
      conn = conn |> Plug.Conn.put_resp_content_type("text/html") |> Plug.Conn.send_chunked(200)
      {:ok, conn} = Plug.Conn.chunk(conn, "<!--" <> String.duplicate("x", 1_999_000))
      {:ok, conn} = Plug.Conn.chunk(conn, String.duplicate("x", 10_000))
      {:ok, conn} = Plug.Conn.chunk(conn, "--><p>Doba 80 zł</p>")
      conn
    end)

    assert {:ok, %{text: text}} = HTTP.fetch_text("https://hotel-testowy.example/")
    assert String.starts_with?(text, "<!--xxx")
    refute text =~ "Doba"
    assert String.length(text) == 15_000
  end

  defp html(conn, body) do
    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.send_resp(200, body)
  end

  defp redirect(conn, location) do
    conn
    |> Plug.Conn.put_resp_header("location", location)
    |> Plug.Conn.send_resp(302, "")
  end
end
