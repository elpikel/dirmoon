defmodule Dirmoon.PageSpeed.NotConfigured do
  @moduledoc """
  The PageSpeed adapter used when no key is configured: every check fails
  with `:page_speed_not_configured`.
  """

  @behaviour Dirmoon.PageSpeed

  @impl Dirmoon.PageSpeed
  def check(_request), do: {:error, :page_speed_not_configured}
end
