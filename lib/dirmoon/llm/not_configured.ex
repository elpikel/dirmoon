defmodule Dirmoon.LLM.NotConfigured do
  @moduledoc """
  The LLM adapter used when no provider is configured: every request fails
  with `:llm_not_configured`.
  """

  @behaviour Dirmoon.LLM

  @impl Dirmoon.LLM
  def structured(_request), do: {:error, :llm_not_configured}
end
