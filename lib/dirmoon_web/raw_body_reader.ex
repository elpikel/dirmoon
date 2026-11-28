defmodule DirmoonWeb.RawBodyReader do
  @moduledoc """
  The `Plug.Parsers` body reader. It reads the body like
  `Plug.Conn.read_body/2` and, for the Stripe webhook only, also keeps the
  bytes as received: Stripe signs the raw body, and the parsed params can't
  give it back. Every chunk read is appended, so a body read in several
  chunks is kept whole. Stripe's events are small, so the webhook's body is
  read up to 1,000,000 bytes; a larger one is refused by the parser with
  413. Other paths keep nothing and their read options are untouched.
  """

  @kept_paths [["webhooks", "stripe"]]
  @kept_body_max_bytes 1_000_000

  def read_body(%Plug.Conn{path_info: path_info} = conn, opts) when path_info in @kept_paths do
    case Plug.Conn.read_body(conn, at_most_kept_body_max(opts)) do
      {status, chunk, conn} when status in [:ok, :more] -> {status, chunk, append(conn, chunk)}
      {:error, _reason} = error -> error
    end
  end

  def read_body(conn, opts), do: Plug.Conn.read_body(conn, opts)

  @doc """
  The body kept for this request, or nil when none was read or the path
  keeps none.
  """
  def raw_body(%Plug.Conn{private: private}), do: Map.get(private, :raw_body)

  defp at_most_kept_body_max(opts),
    do: Keyword.update(opts, :length, @kept_body_max_bytes, &min(&1, @kept_body_max_bytes))

  defp append(conn, chunk), do: Plug.Conn.put_private(conn, :raw_body, (raw_body(conn) || "") <> chunk)
end
