defmodule Dirmoon.SpellingTest do
  use ExUnit.Case, async: true

  alias Dirmoon.Spelling

  doctest Spelling

  test "spellings of one phrase with and without Polish letters compare equal" do
    assert Spelling.without_diacritics("Wypożyczalnia łyżew") == Spelling.without_diacritics("wypozyczalnia LYZEW")
  end

  test "every Polish letter becomes its plain Latin letter" do
    assert Spelling.without_diacritics("ąćęłńóśźż ĄĆĘŁŃÓŚŹŻ") == "acelnoszz acelnoszz"
  end

  test "a text without Polish letters has none to count" do
    assert Spelling.diacritic_count("wypozyczalnia lyzew") == 0
  end

  test "upper-case Polish letters count like lower-case ones" do
    assert Spelling.diacritic_count("ŁYŻWY łyżwy") == 4
  end
end
