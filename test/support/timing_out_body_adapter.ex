defmodule DirmoonWeb.TimingOutBodyAdapter do
  @moduledoc """
  A `Plug.Conn` adapter whose request body never arrives: reading it fails
  with `:timeout`, as Bandit's does when a client stops sending.
  """
  def read_req_body(_state, _opts), do: {:error, :timeout}
end
