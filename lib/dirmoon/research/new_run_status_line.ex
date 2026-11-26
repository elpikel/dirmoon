defmodule Dirmoon.Research.NewRunStatusLine do
  @moduledoc """
  The status sentence of the new research screen: one first-person
  line built from the form's chosen Mode, never by the LLM. See
  `docs/design/README.md` section 8.2, `Dirmoon.Research.StatusLine` for a
  run's sentence and `Dirmoon.Research.RunsStatusLine` for the runs list.
  """

  @new_idea_sentence "Describe the business and I'll find what people really type into Google and how many times a month they type it."
  @existing_site_sentence "Describe the business and give its domain. I'll also check which searches the site already shows up for."

  @doc """
  The sentence for the chosen Mode (`nil` reads as a New Idea).
  """
  def sentence(%{mode: :existing_site}), do: @existing_site_sentence
  def sentence(%{mode: mode}) when mode in [:new_idea, nil], do: @new_idea_sentence
end
