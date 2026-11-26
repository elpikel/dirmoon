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

  test "a page on an international host is requested at the host's ASCII form" do
    test_pid = self()

    Req.Test.stub(HTTP, fn conn ->
      send(test_pid, {:requested, conn.host})
      html(conn, "<p>Żółw</p>")
    end)

    assert {:ok, %{text: "Żółw", url: "https://xn--w-uga1v8h.pl/oferta"}} = HTTP.fetch_text("https://żółw.pl/oferta")
    assert_received {:requested, "xn--w-uga1v8h.pl"}
  end

  test "a redirect to an international host is followed at the host's ASCII form" do
    test_pid = self()

    Req.Test.stub(HTTP, fn
      %Plug.Conn{host: "hotel-testowy.example"} = conn ->
        redirect(conn, "https://münchen.de/hotel")

      conn ->
        send(test_pid, {:requested, conn.host})
        html(conn, "<p>Hotel</p>")
    end)

    assert {:ok, %{status: 200, url: "https://xn--mnchen-3ya.de/hotel", redirects: ["https://hotel-testowy.example/"]}} =
             HTTP.fetch("https://hotel-testowy.example/")

    assert_received {:requested, "xn--mnchen-3ya.de"}
  end

  test "a full-width spelling of a loopback address is refused without a request" do
    test_pid = self()
    Req.Test.stub(HTTP, fn conn -> send(test_pid, {:requested, conn.host}) end)

    assert {:error, "an address in a private network"} = HTTP.fetch("http://１２７.０.０.１/")
    refute_received {:requested, _host}
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

  test "a raw read redirected to an address longer than 2,048 bytes is refused without reading it" do
    test_pid = self()
    too_long = "/" <> String.duplicate("a", 2_048)

    Req.Test.stub(HTTP, fn conn ->
      send(test_pid, {:requested, conn.request_path})
      redirect(conn, too_long)
    end)

    assert {:error, "the address is too long"} = HTTP.fetch("https://hotel-testowy.example/")
    assert_received {:requested, "/"}
    refute_received {:requested, ^too_long}
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
      {:ok, conn} = Plug.Conn.chunk(conn, "<p>" <> String.duplicate("x", 1_999_000))
      {:ok, conn} = Plug.Conn.chunk(conn, String.duplicate("x", 10_000))
      {:ok, conn} = Plug.Conn.chunk(conn, "</p><p>Doba 80 zł</p>")
      conn
    end)

    assert {:ok, %{text: text}} = HTTP.fetch_text("https://hotel-testowy.example/")
    assert String.starts_with?(text, "xxx")
    refute text =~ "Doba"
    assert String.length(text) == 15_000
  end

  test "a read whose caller dies is stopped" do
    test_pid = self()

    Req.Test.stub(HTTP, fn conn ->
      send(test_pid, {:reading, self()})

      receive do
        :never_sent -> conn
      end
    end)

    caller =
      spawn(fn ->
        receive do
          :read -> HTTP.fetch("https://hotel-testowy.example/")
        end
      end)

    Req.Test.allow(HTTP, test_pid, caller)
    send(caller, :read)
    assert_receive {:reading, reading}, 2_000
    reading_ref = Process.monitor(reading)

    Process.exit(caller, :kill)

    assert_receive {:DOWN, ^reading_ref, :process, ^reading, :killed}, 2_000
  end

  @tag :capture_log
  test "a read that crashes is an error and leaves the caller running" do
    Req.Test.stub(HTTP, fn _conn -> raise "the server answered nonsense" end)

    assert {:error, "the page could not be read"} = HTTP.fetch("https://hotel-testowy.example/")
    assert {:error, "the page could not be read"} = HTTP.fetch_text("https://hotel-testowy.example/")
  end

  @tag :capture_log
  test "a read that exits is an error and leaves the caller running" do
    Req.Test.stub(HTTP, fn _conn -> exit(:server_went_away) end)

    assert {:error, "the page could not be read"} = HTTP.fetch("https://hotel-testowy.example/")
  end

  test "an XML answer is not read as text" do
    Req.Test.stub(HTTP, fn conn -> respond(conn, %{status: 200, content_type: "application/xml", body: "<urlset/>"}) end)

    assert {:error, "not an HTML page"} = HTTP.fetch_text("https://hotel-testowy.example/sitemap.xml")
  end

  test "a page is read raw with its address, status, content type and body" do
    test_pid = self()

    Req.Test.stub(HTTP, fn conn ->
      send(test_pid, {:request, %{method: conn.method, headers: conn.req_headers}})
      html(conn, "<html><body><h1>Pokoje</h1></body></html>")
    end)

    assert {:ok,
            %{
              url: "https://hotel-testowy.example/pokoje",
              status: 200,
              redirects: [],
              content_type: "text/html",
              body: "<html><body><h1>Pokoje</h1></body></html>"
            }} = HTTP.fetch("https://hotel-testowy.example/pokoje")

    assert_received {:request, %{method: "GET", headers: headers}}
    assert {"user-agent", "Mozilla/5.0 (compatible; PageReader/1.0)"} in headers
  end

  test "a missing page is answered with its status and body" do
    Req.Test.stub(HTTP, fn conn -> respond(conn, %{status: 404, content_type: "text/html", body: "<h1>Brak</h1>"}) end)

    assert {:ok, %{status: 404, body: "<h1>Brak</h1>", url: "https://hotel-testowy.example/brak"}} =
             HTTP.fetch("https://hotel-testowy.example/brak")
  end

  test "a server error is answered with its status" do
    Req.Test.stub(HTTP, fn conn -> respond(conn, %{status: 500, content_type: "text/plain", body: "Error"}) end)

    assert {:ok, %{status: 500, body: "Error"}} = HTTP.fetch("https://hotel-testowy.example/")
  end

  test "a raw read lists every address it was sent through before the final one, in order" do
    Req.Test.stub(HTTP, fn
      %Plug.Conn{request_path: "/"} = conn -> redirect(conn, "/oferta")
      %Plug.Conn{request_path: "/oferta"} = conn -> redirect(conn, "https://www.hotel-testowy.example/oferta/")
      %Plug.Conn{request_path: "/oferta/"} = conn -> html(conn, "<p>Oferta</p>")
    end)

    assert {:ok,
            %{
              url: "https://www.hotel-testowy.example/oferta/",
              status: 200,
              redirects: ["https://hotel-testowy.example/", "https://hotel-testowy.example/oferta"]
            }} = HTTP.fetch("https://hotel-testowy.example/")
  end

  test "a raw read follows up to five redirects" do
    Req.Test.stub(HTTP, fn conn ->
      if String.length(conn.request_path) < 6,
        do: redirect(conn, conn.request_path <> "x"),
        else: html(conn, "<p>Koniec</p>")
    end)

    assert {:ok, %{url: "https://hotel-testowy.example/xxxxx", redirects: redirects}} =
             HTTP.fetch("https://hotel-testowy.example/")

    assert redirects == Enum.map(["", "x", "xx", "xxx", "xxxx"], &("https://hotel-testowy.example/" <> &1))
  end

  test "a raw read gives up after five redirects" do
    Req.Test.stub(HTTP, fn conn -> redirect(conn, conn.request_path <> "x") end)

    assert {:error, "too many redirects"} = HTTP.fetch("https://hotel-testowy.example/")
  end

  test "a raw read refuses a redirect to a local address without reading it" do
    test_pid = self()

    Req.Test.stub(HTTP, fn conn ->
      send(test_pid, {:requested, conn.host})
      redirect(conn, "http://localhost:4000/admin")
    end)

    assert {:error, "a local address"} = HTTP.fetch("https://hotel-testowy.example/")
    assert_received {:requested, "hotel-testowy.example"}
    refute_received {:requested, "localhost"}
  end

  test "a raw read refuses a redirect to a private network address without reading it" do
    test_pid = self()

    Req.Test.stub(HTTP, fn conn ->
      send(test_pid, {:requested, conn.host})
      redirect(conn, "http://10.0.0.5/")
    end)

    assert {:error, "an address in a private network"} = HTTP.fetch("https://hotel-testowy.example/")
    refute_received {:requested, "10.0.0.5"}
  end

  test "a raw read refuses an address that may not be read without a request" do
    assert {:error, "a local address"} = HTTP.fetch("http://localhost:4000/")
  end

  test "a raw read of a redirect without an address is an error" do
    Req.Test.stub(HTTP, fn conn -> Plug.Conn.send_resp(conn, 301, "") end)

    assert {:error, "redirect without an address"} = HTTP.fetch("https://hotel-testowy.example/")
  end

  test "a raw read reads an XML sitemap" do
    for content_type <- ["application/xml", "text/xml"] do
      Req.Test.stub(HTTP, fn conn -> respond(conn, %{status: 200, content_type: content_type, body: "<urlset/>"}) end)

      assert {:ok, %{content_type: ^content_type, body: "<urlset/>"}} =
               HTTP.fetch("https://hotel-testowy.example/sitemap.xml")
    end
  end

  test "a raw read reads XHTML and plain text" do
    for content_type <- ["application/xhtml+xml", "text/plain"] do
      Req.Test.stub(HTTP, fn conn -> respond(conn, %{status: 200, content_type: content_type, body: "Pokoje"}) end)

      assert {:ok, %{content_type: ^content_type, body: "Pokoje"}} = HTTP.fetch("https://hotel-testowy.example/")
    end
  end

  test "a raw read gives the content type without its parameters, in lower case" do
    Req.Test.stub(HTTP, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "Text/HTML; charset=UTF-8")
      |> Plug.Conn.send_resp(200, "<p>Pokoje</p>")
    end)

    assert {:ok, %{content_type: "text/html", body: "<p>Pokoje</p>"}} = HTTP.fetch("https://hotel-testowy.example/")
  end

  test "a raw read of something other than a page answers its content type and no body" do
    Req.Test.stub(HTTP, fn conn ->
      respond(conn, %{status: 200, content_type: "application/pdf", body: "%PDF-1.7 Doba 80 zł"})
    end)

    assert {:ok, %{status: 200, content_type: "application/pdf", body: ""}} =
             HTTP.fetch("https://hotel-testowy.example/cennik.pdf")
  end

  test "a raw read of an answer without a content type answers no body" do
    Req.Test.stub(HTTP, fn conn ->
      conn |> Plug.Conn.delete_resp_header("content-type") |> Plug.Conn.send_resp(200, "Pokoje")
    end)

    assert {:ok, %{status: 200, content_type: nil, body: ""}} = HTTP.fetch("https://hotel-testowy.example/")
  end

  test "a raw read downloads only the first two megabytes" do
    Req.Test.stub(HTTP, fn conn ->
      conn = conn |> Plug.Conn.put_resp_content_type("text/html") |> Plug.Conn.send_chunked(200)
      {:ok, conn} = Plug.Conn.chunk(conn, String.duplicate("x", 1_999_000))
      {:ok, conn} = Plug.Conn.chunk(conn, String.duplicate("y", 10_000))
      {:ok, conn} = Plug.Conn.chunk(conn, "<p>Doba 80 zł</p>")
      conn
    end)

    assert {:ok, %{body: body}} = HTTP.fetch("https://hotel-testowy.example/")
    assert byte_size(body) == 2_000_000
    refute body =~ "Doba"
  end

  test "a raw read that cannot connect is an error" do
    Req.Test.stub(HTTP, &Req.Test.transport_error(&1, :timeout))

    assert {:error, message} = HTTP.fetch("https://hotel-testowy.example/")
    assert message =~ "timeout"
  end

  defp respond(conn, %{status: status, content_type: content_type, body: body}) do
    conn
    |> Plug.Conn.put_resp_header("content-type", content_type)
    |> Plug.Conn.send_resp(status, body)
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
