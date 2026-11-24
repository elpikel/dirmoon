defmodule Dirmoon do
  @moduledoc """
  Dirmoon keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  @doc """
  Whether a demo adapter stands in for a real provider, so the app shows the
  "DANE TESTOWE" banner. Set by `config :dirmoon, :demo_data`.
  """
  def demo_data?, do: Application.get_env(:dirmoon, :demo_data, false)

  @doc """
  The prefix that marks Demo Data text as synthetic. It is lower case in
  parentheses, so it is never mistaken for a Placeholder.
  """
  def demo_marker, do: "(demo)"
end
