defmodule Dirmoon.Research.NewRunStatusLine do
  @moduledoc """
  The status sentence of the new research screen: one first-person
  line built from the form's state (the chosen Mode and whether the Account
  has a Search Console Connection), never by the LLM. See
  `docs/design/README.md` section 8.2, `Dirmoon.Research.StatusLine` for a
  run's sentence and `Dirmoon.Research.RunsStatusLine` for the runs list.
  """

  @new_idea_sentence "Describe the business and I'll find the phrases people really type and count how many search for them."
  @existing_site_sentence "Describe the business and give its domain. I'll also check which phrases the site already shows up for."
  @existing_site_without_search_console_sentence "Describe the business and give its domain. Without Search Console I'll skip the site's current positions."

  @doc """
  The sentence for the chosen Mode (`nil` reads as a New Idea) and the
  Account's Search Console Connection.
  """
  def sentence(%{mode: :existing_site, search_console_connected?: true}), do: @existing_site_sentence

  def sentence(%{mode: :existing_site, search_console_connected?: false}),
    do: @existing_site_without_search_console_sentence

  def sentence(%{mode: mode}) when mode in [:new_idea, nil], do: @new_idea_sentence
end
