defmodule DirmoonWeb.RawBodyReaderTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias DirmoonWeb.RawBodyReader

  test "the Stripe webhook's body is kept as read" do
    conn = conn(:post, "/webhooks/stripe", ~s({"id":"evt"}))

    assert {:ok, ~s({"id":"evt"}), conn} = RawBodyReader.read_body(conn, [])
    assert RawBodyReader.raw_body(conn) == ~s({"id":"evt"})
  end

  test "a body read in several chunks is kept whole" do
    conn = conn(:post, "/webhooks/stripe", "0123456789")

    assert {:more, "01234", conn} = RawBodyReader.read_body(conn, length: 5)
    assert RawBodyReader.raw_body(conn) == "01234"
    assert {:ok, "56789", conn} = RawBodyReader.read_body(conn, length: 5)
    assert RawBodyReader.raw_body(conn) == "0123456789"
  end

  test "the webhook's body is read up to 1,000,000 bytes whatever length the caller allows" do
    conn = conn(:post, "/webhooks/stripe", String.duplicate("a", 1_000_001))

    assert {:more, chunk, conn} = RawBodyReader.read_body(conn, length: 8_000_000)
    assert byte_size(chunk) == 1_000_000
    assert byte_size(RawBodyReader.raw_body(conn)) == 1_000_000
  end

  test "the webhook's body is read up to 1,000,000 bytes when the caller sets no length" do
    conn = conn(:post, "/webhooks/stripe", String.duplicate("a", 1_000_001))

    assert {:more, chunk, _conn} = RawBodyReader.read_body(conn, [])
    assert byte_size(chunk) == 1_000_000
  end

  test "another path's body is read up to the length the caller allows" do
    body = String.duplicate("a", 1_000_001)
    conn = conn(:post, "/sign-up", body)

    assert {:ok, ^body, _conn} = RawBodyReader.read_body(conn, length: 8_000_000)
  end

  test "a body that fails to arrive gives the adapter's error and keeps nothing" do
    conn = %{conn(:post, "/webhooks/stripe", "") | adapter: {DirmoonWeb.TimingOutBodyAdapter, nil}}

    assert RawBodyReader.read_body(conn, []) == {:error, :timeout}
  end

  test "another path's body is read but not kept" do
    conn = conn(:post, "/sign-up", "user[email]=someone")

    assert {:ok, "user[email]=someone", conn} = RawBodyReader.read_body(conn, [])
    assert RawBodyReader.raw_body(conn) == nil
  end
end
