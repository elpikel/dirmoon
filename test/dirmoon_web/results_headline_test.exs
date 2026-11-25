defmodule DirmoonWeb.ResultsHeadlineTest do
  use ExUnit.Case, async: true

  alias DirmoonWeb.ResultsHeadline

  doctest ResultsHeadline

  test "nine Niches of which three are worth going after" do
    assert ResultsHeadline.text(%{niches: 9, worth: 3}) == "Nine topics. Three worth going after."
  end

  test "no Niche at all" do
    assert ResultsHeadline.text(%{niches: 0, worth: 0}) == "Zero topics. None worth going after."
  end

  test "one Niche takes the singular" do
    assert ResultsHeadline.text(%{niches: 1, worth: 1}) == "One topic. One worth going after."
  end

  test "two or more Niches take the plural" do
    assert Enum.map(2..4, &ResultsHeadline.text(%{niches: &1, worth: 0})) == [
             "Two topics. None worth going after.",
             "Three topics. None worth going after.",
             "Four topics. None worth going after."
           ]
  end

  test "Niches up to twenty are counted in words" do
    assert ResultsHeadline.text(%{niches: 5, worth: 0}) =~ ~r/^Five topics\. /
    assert ResultsHeadline.text(%{niches: 12, worth: 0}) =~ ~r/^Twelve topics\. /
    assert ResultsHeadline.text(%{niches: 20, worth: 0}) =~ ~r/^Twenty topics\. /
  end

  test "more than twenty Niches are digits" do
    assert ResultsHeadline.text(%{niches: 25, worth: 21}) == "25 topics. 21 worth going after."
  end

  test "none worth going after says none is" do
    assert ResultsHeadline.text(%{niches: 6, worth: 0}) == "Six topics. None worth going after."
  end

  test "the number worth going after is counted in words" do
    assert Enum.map([1, 2, 13], &ResultsHeadline.text(%{niches: 14, worth: &1})) == [
             "Fourteen topics. One worth going after.",
             "Fourteen topics. Two worth going after.",
             "Fourteen topics. Thirteen worth going after."
           ]
  end

  test "before the Niches are scored the heading speaks of the Phrases so far" do
    assert ResultsHeadline.text(:before_scoring) == "What people type into Google, so far."
  end

  test "the status line names the best Niche and how weak its competition is" do
    best = %{name: "Lake cruises", competition: %{verdict: :weak, holders: "forums, guides and blogs"}}

    assert ResultsHeadline.status_line(best) ==
             "The best chance is Lake cruises. Weak competition: easy to get onto Google's first page, which holds mostly forums, guides and blogs."
  end

  test "the status line names medium and strong competition" do
    medium = %{name: "Lake cruises", competition: %{verdict: :medium, holders: "big portals"}}
    strong = %{name: "Lake cruises", competition: %{verdict: :strong, holders: "businesses like yours"}}

    assert ResultsHeadline.status_line(medium) =~
             "Medium competition: Google's first page is a mix of big portals, so getting onto it is possible, but not at once."

    assert ResultsHeadline.status_line(strong) =~
             "Strong competition: hard to get onto Google's first page, which holds mostly businesses like yours."
  end

  test "the status line says so when the best Niche's competition wasn't checked" do
    assert ResultsHeadline.status_line(%{name: "Lake cruises", competition: nil}) ==
             "The best chance is Lake cruises. I haven't checked who is on Google's first page yet."
  end

  test "the status line says so when no Niche is left" do
    assert ResultsHeadline.status_line(nil) =~ "No topic is left to choose."
  end
end
