defmodule Dirmoon.Hosting.NotConfigured do
  @moduledoc """
  The hosting adapter used when no Netlify token is configured: every call
  fails with `:hosting_not_configured`.
  """

  @behaviour Dirmoon.Hosting

  @impl Dirmoon.Hosting
  def create_site(_request), do: {:error, :hosting_not_configured}

  @impl Dirmoon.Hosting
  def deploy(_request), do: {:error, :hosting_not_configured}
end
