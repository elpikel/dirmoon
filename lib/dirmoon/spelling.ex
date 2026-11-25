defmodule Dirmoon.Spelling do
  @moduledoc """
  Compares spellings of Polish-market Phrases: people type the same Phrase
  with and without Polish letters ("wypożyczalnia łyżew", "wypozyczalnia
  lyzew"), and the keyword API returns each spelling as its own Phrase.
  """

  @plain_letters %{
    "ą" => "a",
    "ć" => "c",
    "ę" => "e",
    "ł" => "l",
    "ń" => "n",
    "ó" => "o",
    "ś" => "s",
    "ź" => "z",
    "ż" => "z"
  }
  @diacritic_letters Map.keys(@plain_letters)

  @doc """
  The text in lower case with Polish letters replaced by their plain Latin
  ones, so spellings of one Phrase compare equal.

      iex> Dirmoon.Spelling.without_diacritics("Wypożyczalnia ŁYŻEW")
      "wypozyczalnia lyzew"
  """
  def without_diacritics(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(@diacritic_letters, &Map.fetch!(@plain_letters, &1))
  end

  @doc """
  How many Polish letters (ą, ć, ę, ł, ń, ó, ś, ź, ż) the text has.

      iex> Dirmoon.Spelling.diacritic_count("Wypożyczalnia ŁYŻEW")
      3
  """
  def diacritic_count(text) when is_binary(text) do
    lower_case = String.downcase(text)
    String.length(lower_case) - String.length(String.replace(lower_case, @diacritic_letters, ""))
  end
end
