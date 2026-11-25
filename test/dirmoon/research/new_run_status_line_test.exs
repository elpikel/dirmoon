defmodule Dirmoon.Research.NewRunStatusLineTest do
  use ExUnit.Case, async: true

  alias Dirmoon.Research.NewRunStatusLine

  test "for a new idea it promises the phrases people type and how many search for them" do
    assert NewRunStatusLine.sentence(%{mode: :new_idea, search_console_connected?: false}) ==
             "Describe the business and I'll find what people really type into Google and how many times a month they type it."
  end

  test "for a new idea a Search Console connection changes nothing" do
    assert NewRunStatusLine.sentence(%{mode: :new_idea, search_console_connected?: true}) ==
             NewRunStatusLine.sentence(%{mode: :new_idea, search_console_connected?: false})
  end

  test "for an existing site with Search Console it asks for the domain and promises current positions" do
    assert NewRunStatusLine.sentence(%{mode: :existing_site, search_console_connected?: true}) ==
             "Describe the business and give its domain. I'll also check which searches the site already shows up for."
  end

  test "for an existing site without Search Console it says current positions will be skipped" do
    assert NewRunStatusLine.sentence(%{mode: :existing_site, search_console_connected?: false}) ==
             "Describe the business and give its domain. Without Search Console I'll skip where the site already shows up on Google."
  end

  test "with no Mode chosen it reads as a new idea" do
    assert NewRunStatusLine.sentence(%{mode: nil, search_console_connected?: true}) ==
             NewRunStatusLine.sentence(%{mode: :new_idea, search_console_connected?: true})
  end
end
