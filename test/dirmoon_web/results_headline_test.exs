defmodule DirmoonWeb.ResultsHeadlineTest do
  use ExUnit.Case, async: true

  alias DirmoonWeb.ResultsHeadline

  doctest ResultsHeadline

  test "nine Niches of which three are worth going after" do
    assert ResultsHeadline.text(%{niches: 9, worth: 3}) == "Nine niches. Three worth going after."
  end

  test "no Niche at all" do
    assert ResultsHeadline.text(%{niches: 0, worth: 0}) == "Zero niches. None worth going after."
  end

  test "one Niche takes the singular" do
    assert ResultsHeadline.text(%{niches: 1, worth: 1}) == "One niche. One worth going after."
  end

  test "two or more Niches take the plural" do
    assert Enum.map(2..4, &ResultsHeadline.text(%{niches: &1, worth: 0})) == [
             "Two niches. None worth going after.",
             "Three niches. None worth going after.",
             "Four niches. None worth going after."
           ]
  end

  test "Niches up to twenty are counted in words" do
    assert ResultsHeadline.text(%{niches: 5, worth: 0}) =~ ~r/^Five niches\. /
    assert ResultsHeadline.text(%{niches: 12, worth: 0}) =~ ~r/^Twelve niches\. /
    assert ResultsHeadline.text(%{niches: 20, worth: 0}) =~ ~r/^Twenty niches\. /
  end

  test "more than twenty Niches are digits" do
    assert ResultsHeadline.text(%{niches: 25, worth: 21}) == "25 niches. 21 worth going after."
  end

  test "none worth going after says none is" do
    assert ResultsHeadline.text(%{niches: 6, worth: 0}) == "Six niches. None worth going after."
  end

  test "the number worth going after is counted in words" do
    assert Enum.map([1, 2, 13], &ResultsHeadline.text(%{niches: 14, worth: &1})) == [
             "Fourteen niches. One worth going after.",
             "Fourteen niches. Two worth going after.",
             "Fourteen niches. Thirteen worth going after."
           ]
  end

  test "before the Niches are scored the heading speaks of the Phrases so far" do
    assert ResultsHeadline.text(:before_scoring) == "Phrases so far."
  end

  test "the status line names the best Niche and how weak its competition is" do
    best = %{name: "Lake cruises", competition: %{verdict: :weak, holders: "forums, guides and blogs"}}

    assert ResultsHeadline.status_line(best) ==
             "The best chance is Lake cruises. Weak results lead the first page: forums, guides and blogs."
  end

  test "the status line names medium and strong competition" do
    medium = %{name: "Lake cruises", competition: %{verdict: :medium, holders: "big portals"}}
    strong = %{name: "Lake cruises", competition: %{verdict: :strong, holders: "businesses like yours"}}

    assert ResultsHeadline.status_line(medium) =~ "The competition is medium: big portals."
    assert ResultsHeadline.status_line(strong) =~ "The competition is strong: businesses like yours."
  end

  test "the status line says so when the best Niche's competition wasn't checked" do
    assert ResultsHeadline.status_line(%{name: "Lake cruises", competition: nil}) ==
             "The best chance is Lake cruises. I haven't checked the competition yet."
  end

  test "the status line says so when no Niche is left" do
    assert ResultsHeadline.status_line(nil) =~ "No niche is left to choose."
  end
end
