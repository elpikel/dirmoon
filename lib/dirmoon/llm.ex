defmodule Dirmoon.LLM do
  @moduledoc """
  The seam to the language model. A Step sends one structured request and
  gets back a map with string keys plus what the call cost; the adapter is
  chosen by `config :dirmoon, :llm_adapter`.

  A request names its `task` (one of `tasks/0`), carries the `system` and
  `prompt` text, the JSON-Schema-like `schema` the answer must follow and the
  structured `input` the prompt was built from.
  """

  @type request :: %{
          task: atom(),
          system: String.t(),
          prompt: String.t(),
          schema: map(),
          input: map()
        }

  @callback structured(request()) :: {:ok, map(), Decimal.t()} | {:error, term()}

  @tasks [:seeds, :filter_and_group, :label_serp, :brief]

  @doc "Sends the request to the configured adapter."
  @spec structured(request()) :: {:ok, map(), Decimal.t()} | {:error, term()}
  def structured(request), do: adapter().structured(request)

  @doc "The tasks a Step may ask the LLM for."
  def tasks, do: @tasks

  defp adapter, do: Application.fetch_env!(:dirmoon, :llm_adapter)
end
