defmodule Dirmoon.Research.NewRunStatusLineTest do
  use ExUnit.Case, async: true

  alias Dirmoon.Research.NewRunStatusLine

  test "for a new idea it promises the phrases people type and how many search for them" do
    assert NewRunStatusLine.sentence(%{mode: :new_idea}) ==
             "Describe the business and I'll find what people really type into Google and how many times a month they type it."
  end

  test "for an existing site it asks for the domain and promises current positions" do
    assert NewRunStatusLine.sentence(%{mode: :existing_site}) ==
             "Describe the business and give its domain. I'll also check which searches the site already shows up for."
  end

  test "with no Mode chosen it reads as a new idea" do
    assert NewRunStatusLine.sentence(%{mode: nil}) == NewRunStatusLine.sentence(%{mode: :new_idea})
  end
end
