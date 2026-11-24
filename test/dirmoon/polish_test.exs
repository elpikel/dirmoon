defmodule Dirmoon.PolishTest do
  use ExUnit.Case, async: true

  alias Dirmoon.Polish

  doctest Polish

  @phrase_forms %{one: "fraza startowa", few: "frazy startowe", many: "fraz startowych"}

  test "one takes the singular form" do
    assert Polish.plural(1, @phrase_forms) == "fraza startowa"
  end

  test "two to four take the few form" do
    assert Enum.map([2, 3, 4], &Polish.plural(&1, @phrase_forms)) == List.duplicate("frazy startowe", 3)
  end

  test "zero and five to twenty-one take the many form" do
    counts = [0 | Enum.to_list(5..21)]

    assert Enum.map(counts, &Polish.plural(&1, @phrase_forms)) == List.duplicate("fraz startowych", length(counts))
  end

  test "twelve to fourteen take the many form" do
    assert Enum.map([12, 13, 14, 112, 113], &Polish.plural(&1, @phrase_forms)) ==
             List.duplicate("fraz startowych", 5)
  end

  test "numbers ending in two to four above twenty take the few form" do
    assert Enum.map([22, 23, 24, 102, 1034], &Polish.plural(&1, @phrase_forms)) == List.duplicate("frazy startowe", 5)
  end

  test "numbers ending in five to one above twenty take the many form" do
    assert Enum.map([25, 31, 101, 111], &Polish.plural(&1, @phrase_forms)) == List.duplicate("fraz startowych", 4)
  end

  test "a dollar amount shows two decimals after a comma" do
    assert Polish.usd(Decimal.new("1.5")) == "$1,50"
  end

  test "a dollar amount is rounded to cents" do
    assert Polish.usd(Decimal.new("0.0775")) == "$0,08"
  end

  test "nothing spent shows as zero dollars and zero cents" do
    assert Polish.usd(Decimal.new(0)) == "$0,00"
  end

  test "counts of a feminine noun up to twenty read as words" do
    assert Enum.map([0, 1, 2, 5, 12, 20], &Polish.feminine_number/1) ==
             ["zero", "jedna", "dwie", "pięć", "dwanaście", "dwadzieścia"]
  end

  test "counts above twenty read as digits" do
    assert Enum.map([21, 137], &Polish.feminine_number/1) == ["21", "137"]
  end

  test "whole numbers group their thousands with a non-breaking space" do
    assert Enum.map([0, 999, 1000, 73_105, 4_000_001], &Polish.integer/1) ==
             ["0", "999", "1\u00A0000", "73\u00A0105", "4\u00A0000\u00A0001"]
  end

  test "decimals are rounded and written with a decimal comma" do
    assert Polish.decimal(Decimal.new("13.27"), 1) == "13,3"
    assert Polish.decimal(Decimal.new("7"), 1) == "7,0"
  end

  test "money in dollars reads as dollars and other currencies follow the amount" do
    assert Polish.money(Decimal.new("0.37"), "USD") == "$0,37"
    assert Polish.money(Decimal.new("0.37"), "EUR") == "0,37 EUR"
  end

  test "negative whole numbers keep their minus sign before the grouped digits" do
    assert Enum.map([-7, -1000, -1_234_567], &Polish.integer/1) ==
             ["-7", "-1\u00A0000", "-1\u00A0234\u00A0567"]
  end

  test "negative decimals keep their minus sign" do
    assert Polish.decimal(Decimal.new("-2.345"), 2) == "-2,35"
  end

  test "zero places round to a whole number without a comma" do
    assert Polish.decimal(Decimal.new("8.6"), 0) == "9"
  end

  test "large counts pick their plural form from the last two digits" do
    assert Polish.plural(1_000_002, @phrase_forms) == "frazy startowe"
    assert Polish.plural(1_000_012, @phrase_forms) == "fraz startowych"
    assert Polish.plural(1_000_001, @phrase_forms) == "fraz startowych"
  end

  test "zero reads as the word for zero" do
    assert Polish.feminine_number(0) == "zero"
    assert Polish.feminine_number(20) == "dwadzieścia"
  end
end
