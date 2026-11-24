defmodule Dirmoon.SearchConsole.Client.NotConfigured do
  @moduledoc """
  The Search Console client used when no Google OAuth credentials are
  configured: every call fails with `:search_console_not_configured`.
  """

  @behaviour Dirmoon.SearchConsole.Client

  alias Dirmoon.SearchConsole.Client

  @impl Client
  def authorize_url(_request), do: not_configured()

  @impl Client
  def exchange_code(_request), do: not_configured()

  @impl Client
  def refresh_access_token(_request), do: not_configured()

  @impl Client
  def query(_request), do: not_configured()

  defp not_configured, do: {:error, :search_console_not_configured}
end
