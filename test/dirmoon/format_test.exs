defmodule Dirmoon.FormatTest do
  use ExUnit.Case, async: true

  alias Dirmoon.Format

  doctest Format

  @phrase_forms %{one: "seed phrase", other: "seed phrases"}

  test "one takes the singular form" do
    assert Format.plural(1, @phrase_forms) == "seed phrase"
  end

  test "zero and every count above one take the plural form" do
    counts = [0, 2, 3, 5, 11, 12, 21, 101, 1_000_001]

    assert Enum.map(counts, &Format.plural(&1, @phrase_forms)) == List.duplicate("seed phrases", length(counts))
  end

  test "a dollar amount shows two decimals after a point" do
    assert Format.usd(Decimal.new("1.5")) == "$1.50"
  end

  test "a dollar amount is rounded to cents" do
    assert Format.usd(Decimal.new("0.0775")) == "$0.08"
  end

  test "nothing spent shows as zero dollars and zero cents" do
    assert Format.usd(Decimal.new(0)) == "$0.00"
  end

  test "counts up to twenty read as words" do
    assert Enum.map([0, 1, 2, 5, 12, 20], &Format.number_word/1) == ["zero", "one", "two", "five", "twelve", "twenty"]
  end

  test "counts above twenty read as digits" do
    assert Enum.map([21, 137], &Format.number_word/1) == ["21", "137"]
  end

  test "whole numbers group their thousands with a comma" do
    assert Enum.map([0, 999, 1000, 73_105, 4_000_001], &Format.integer/1) ==
             ["0", "999", "1,000", "73,105", "4,000,001"]
  end

  test "decimals are rounded and written with a decimal point" do
    assert Format.decimal(Decimal.new("13.27"), 1) == "13.3"
    assert Format.decimal(Decimal.new("7"), 1) == "7.0"
  end

  test "money in dollars reads as dollars and other currencies follow the amount" do
    assert Format.money(Decimal.new("0.37"), "USD") == "$0.37"
    assert Format.money(Decimal.new("0.37"), "EUR") == "0.37 EUR"
  end

  test "negative whole numbers keep their minus sign before the grouped digits" do
    assert Enum.map([-7, -1000, -1_234_567], &Format.integer/1) == ["-7", "-1,000", "-1,234,567"]
  end

  test "negative decimals keep their minus sign" do
    assert Format.decimal(Decimal.new("-2.345"), 2) == "-2.35"
  end

  test "zero places round to a whole number without a point" do
    assert Format.decimal(Decimal.new("8.6"), 0) == "9"
  end
end
