defmodule Dirmoon.Research.NewRunStatusLineTest do
  use ExUnit.Case, async: true

  alias Dirmoon.Research.NewRunStatusLine

  test "for a new idea it promises the phrases people type and how many search for them" do
    assert NewRunStatusLine.sentence(%{mode: :new_idea, search_console_connected?: false}) ==
             "Opisz biznes, a znajdę frazy, które ludzie naprawdę wpisują, i policzę, ile osób ich szuka."
  end

  test "for a new idea a Search Console connection changes nothing" do
    assert NewRunStatusLine.sentence(%{mode: :new_idea, search_console_connected?: true}) ==
             NewRunStatusLine.sentence(%{mode: :new_idea, search_console_connected?: false})
  end

  test "for an existing site with Search Console it asks for the domain and promises current positions" do
    assert NewRunStatusLine.sentence(%{mode: :existing_site, search_console_connected?: true}) ==
             "Opisz biznes i podaj domenę. Sprawdzę też, na które frazy strona już jest widoczna."
  end

  test "for an existing site without Search Console it says current positions will be skipped" do
    assert NewRunStatusLine.sentence(%{mode: :existing_site, search_console_connected?: false}) ==
             "Opisz biznes i podaj domenę. Bez Search Console pominę obecne pozycje strony."
  end

  test "with no Mode chosen it reads as a new idea" do
    assert NewRunStatusLine.sentence(%{mode: nil, search_console_connected?: true}) ==
             NewRunStatusLine.sentence(%{mode: :new_idea, search_console_connected?: true})
  end
end
