defmodule Dirmoon.Format do
  @moduledoc """
  Numbers, money and noun forms as the English interface writes them, such as
  the noun that agrees with a count ("1 phrase", "12 phrases"), the word for a
  small number ("nine"), and numbers and money ("12,400", "8.5", "$0.24").
  """

  @thousands_separator ","

  @number_words ~w(zero one two three four five six seven eight nine ten
    eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen
    nineteen twenty)

  @doc """
  Picks the form of a noun that agrees with `count`: `one` for 1, `other`
  for every other count.

      iex> Dirmoon.Format.plural(3, %{one: "question", other: "questions"})
      "questions"
  """
  def plural(1, %{one: one}), do: one
  def plural(count, %{other: other}) when is_integer(count) and count >= 0, do: other

  @doc """
  Formats a USD amount with a dollar sign and two decimals.

      iex> Dirmoon.Format.usd(Decimal.new("0.0775"))
      "$0.08"
  """
  def usd(%Decimal{} = amount) do
    "$" <> decimal(amount, 2)
  end

  @doc """
  The word for a count from 0 to #{length(@number_words) - 1}, larger counts
  as digits.

      iex> Dirmoon.Format.number_word(2)
      "two"

      iex> Dirmoon.Format.number_word(22)
      "22"
  """
  def number_word(count) when is_integer(count) and count >= 0 do
    case Enum.at(@number_words, count) do
      nil -> Integer.to_string(count)
      word -> word
    end
  end

  @doc """
  A whole number with its thousands separated by a comma.

      iex> Dirmoon.Format.integer(12400)
      "12,400"
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
  A decimal number rounded to `places` decimals with a decimal point.

      iex> Dirmoon.Format.decimal(Decimal.new("8.46"), 1)
      "8.5"
  """
  def decimal(%Decimal{} = number, places) when is_integer(places) and places >= 0 do
    number
    |> Decimal.round(places)
    |> Decimal.to_string(:normal)
  end

  @doc """
  An amount in the given currency: USD as `usd/1` writes it, any other
  currency after the amount.

      iex> Dirmoon.Format.money(Decimal.new("1.4"), "EUR")
      "1.40 EUR"
  """
  def money(%Decimal{} = amount, "USD"), do: usd(amount)
  def money(%Decimal{} = amount, currency) when is_binary(currency), do: decimal(amount, 2) <> " " <> currency
end
