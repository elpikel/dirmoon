defmodule Dirmoon.Research.NewRunStatusLine do
  @moduledoc """
  The status sentence of the new research screen: one first-person Polish
  line built from the form's state (the chosen Mode and whether the Account
  has a Search Console Connection), never by the LLM. See
  `docs/design/README.md` section 8.2, `Dirmoon.Research.StatusLine` for a
  run's sentence and `Dirmoon.Research.RunsStatusLine` for the runs list.
  """

  @new_idea_sentence "Opisz biznes, a znajdę frazy, które ludzie naprawdę wpisują, i policzę, ile osób ich szuka."
  @existing_site_sentence "Opisz biznes i podaj domenę. Sprawdzę też, na które frazy strona już jest widoczna."
  @existing_site_without_search_console_sentence "Opisz biznes i podaj domenę. Bez Search Console pominę obecne pozycje strony."

  @doc """
  The sentence for the chosen Mode (`nil` reads as a New Idea) and the
  Account's Search Console Connection.
  """
  def sentence(%{mode: :existing_site, search_console_connected?: true}), do: @existing_site_sentence

  def sentence(%{mode: :existing_site, search_console_connected?: false}),
    do: @existing_site_without_search_console_sentence

  def sentence(%{mode: mode}) when mode in [:new_idea, nil], do: @new_idea_sentence
end
