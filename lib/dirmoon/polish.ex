defmodule Dirmoon.Polish do
  @moduledoc """
  Polish grammar the interface needs, such as picking a noun's plural form
  for a count ("1 fraza", "3 frazy", "12 fraz") or the word for a number
  ("dziewięć"), and numbers and money as Polish readers write them
  ("12 400", "8,5", "$0,24").
  """

  @thousands_separator "\u00A0"

  @feminine_number_words ~w(zero jedna dwie trzy cztery pięć sześć siedem osiem dziewięć dziesięć
    jedenaście dwanaście trzynaście czternaście piętnaście szesnaście siedemnaście osiemnaście
    dziewiętnaście dwadzieścia)

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
  Picks the form of a noun that agrees with `count`: `one` for 1, `few` for
  counts ending in 2–4 (except 12–14), `many` for everything else.

      iex> Dirmoon.Polish.plural(3, %{one: "pytanie", few: "pytania", many: "pytań"})
      "pytania"
  """
  def plural(1, %{one: one}), do: one

  def plural(count, %{few: few, many: many}) when is_integer(count) and count >= 0 do
    if rem(count, 10) in 2..4 and rem(count, 100) not in 12..14, do: few, else: many
  end

  @doc """
  Formats a USD amount with a dollar sign, two decimals and a decimal comma.

      iex> Dirmoon.Polish.usd(Decimal.new("0.0775"))
      "$0,08"
  """
  def usd(%Decimal{} = amount) do
    "$" <> decimal(amount, 2)
  end

  @doc """
  The word for a count of a feminine noun (a "nisza") from 0 to
  #{length(@feminine_number_words) - 1}, larger counts as digits.

      iex> Dirmoon.Polish.feminine_number(2)
      "dwie"

      iex> Dirmoon.Polish.feminine_number(22)
      "22"
  """
  def feminine_number(count) when is_integer(count) and count >= 0 do
    case Enum.at(@feminine_number_words, count) do
      nil -> Integer.to_string(count)
      word -> word
    end
  end

  @doc """
  A whole number with its thousands separated by a non-breaking space.

      iex> Dirmoon.Polish.integer(12400)
      "12\u00A0400"
  """
  def integer(number) when is_integer(number) and number < 0, do: "-" <> integer(-number)

  def integer(number) when is_integer(number) do
    number
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(@thousands_separator, &Enum.join/1)
    |> String.reverse()
  end

  @doc """
  A decimal number rounded to `places` decimals with a decimal comma.

      iex> Dirmoon.Polish.decimal(Decimal.new("8.46"), 1)
      "8,5"
  """
  def decimal(%Decimal{} = number, places) when is_integer(places) and places >= 0 do
    number
    |> Decimal.round(places)
    |> Decimal.to_string(:normal)
    |> String.replace(".", ",")
  end

  @doc """
  An amount in the given currency: USD as `usd/1` writes it, any other
  currency after the amount.

      iex> Dirmoon.Polish.money(Decimal.new("1.4"), "EUR")
      "1,40 EUR"
  """
  def money(%Decimal{} = amount, "USD"), do: usd(amount)
  def money(%Decimal{} = amount, currency) when is_binary(currency), do: decimal(amount, 2) <> " " <> currency

  @doc """
  The text in lower case with Polish letters replaced by their plain Latin
  ones, so spellings of one phrase compare equal.

      iex> Dirmoon.Polish.without_diacritics("Wypożyczalnia ŁYŻEW")
      "wypozyczalnia lyzew"
  """
  def without_diacritics(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(@diacritic_letters, &Map.fetch!(@plain_letters, &1))
  end

  @doc """
  How many Polish letters (ą, ć, ę, ł, ń, ó, ś, ź, ż) the text has.

      iex> Dirmoon.Polish.diacritic_count("Wypożyczalnia ŁYŻEW")
      3
  """
  def diacritic_count(text) when is_binary(text) do
    lower_case = String.downcase(text)
    String.length(lower_case) - String.length(String.replace(lower_case, @diacritic_letters, ""))
  end
end
