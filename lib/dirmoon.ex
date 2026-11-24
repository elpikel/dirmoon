defmodule Dirmoon do
  @moduledoc """
  Dirmoon keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  @demo_services [
    llm_adapter: {Dirmoon.LLM.Demo, "model językowy (OpenAI)"},
    data_for_seo_adapter: {Dirmoon.DataForSEO.Demo, "frazy i konkurencja (DataForSEO)"},
    search_console_adapter: {Dirmoon.SearchConsole.Client.Demo, "Search Console"},
    hosting_adapter: {Dirmoon.Hosting.Demo, "publikacja (Netlify)"}
  ]

  @doc """
  Whether a demo adapter stands in for a real provider, so the app shows the
  "DANE TESTOWE" banner.
  """
  def demo_data?, do: demo_services() != []

  @doc """
  The Polish names of the external services answered by a demo adapter right
  now, in pipeline order; the "DANE TESTOWE" banner lists them.
  """
  def demo_services do
    for {config_key, {demo_adapter, name}} <- @demo_services,
        Application.get_env(:dirmoon, config_key) == demo_adapter,
        do: name
  end

  @doc """
  The prefix that marks Demo Data text as synthetic. It is lower case in
  parentheses, so it is never mistaken for a Placeholder.
  """
  def demo_marker, do: "(demo)"
end
