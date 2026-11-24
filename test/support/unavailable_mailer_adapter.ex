defmodule Dirmoon.UnavailableMailerAdapter do
  @moduledoc """
  A Swoosh adapter whose every delivery fails, for tests of the paths taken
  when the mail service is down.
  """
  use Swoosh.Adapter

  @impl Swoosh.Adapter
  def deliver(_email, _config), do: {:error, :mail_service_unavailable}
end
