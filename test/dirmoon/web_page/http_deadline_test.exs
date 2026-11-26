defmodule Dirmoon.WebPage.HTTPDeadlineTest do
  use ExUnit.Case, async: false

  alias Dirmoon.WebPage.HTTP

  test "a body that arrives past the read deadline is an error from the read itself" do
    with_read_deadline(0)

    Req.Test.stub(HTTP, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(200, "<p>Pokoje</p>")
    end)

    assert {:error, "the page took too long to read"} = HTTP.fetch("https://hotel-testowy.example/")
  end

  test "a redirect due past the read deadline is not followed" do
    with_read_deadline(0)
    test_pid = self()

    Req.Test.stub(HTTP, fn conn ->
      send(test_pid, {:requested, conn.request_path})

      conn
      |> Plug.Conn.put_resp_header("location", "/oferta")
      |> Plug.Conn.send_resp(302, "")
    end)

    assert {:error, "the page took too long to read"} = HTTP.fetch("https://hotel-testowy.example/")
    assert_received {:requested, "/"}
    refute_received {:requested, "/oferta"}
  end

  test "a page that is not answered within the read deadline is an error and its read is stopped" do
    with_read_deadline(100)
    test_pid = self()

    Req.Test.stub(HTTP, fn conn ->
      send(test_pid, {:reading, self()})

      receive do
        :never_sent -> conn
      end
    end)

    assert {:error, "the page took too long to read"} = HTTP.fetch_text("https://hotel-testowy.example/")
    assert_received {:reading, reading}
    reading_ref = Process.monitor(reading)
    assert_receive {:DOWN, ^reading_ref, :process, ^reading, _reason}, 2_000
  end

  test "a raw read whose redirect is not answered within the read deadline is an error and its read is stopped" do
    with_read_deadline(100)
    test_pid = self()

    Req.Test.stub(HTTP, fn
      %Plug.Conn{request_path: "/"} = conn ->
        conn
        |> Plug.Conn.put_resp_header("location", "/oferta")
        |> Plug.Conn.send_resp(302, "")

      conn ->
        send(test_pid, {:reading, self()})

        receive do
          :never_sent -> conn
        end
    end)

    assert {:error, "the page took too long to read"} = HTTP.fetch("https://hotel-testowy.example/")
    assert_received {:reading, reading}
    reading_ref = Process.monitor(reading)
    assert_receive {:DOWN, ^reading_ref, :process, ^reading, _reason}, 2_000
  end

  defp with_read_deadline(milliseconds) do
    config = Application.get_env(:dirmoon, HTTP)
    Application.put_env(:dirmoon, HTTP, Keyword.put(config, :read_deadline, milliseconds))
    on_exit(fn -> Application.put_env(:dirmoon, HTTP, config) end)
  end
end
