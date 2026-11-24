defmodule DirmoonWeb.ResultsHeadlineTest do
  use ExUnit.Case, async: true

  alias DirmoonWeb.ResultsHeadline

  doctest ResultsHeadline

  test "nine Niches of which three are worth going after" do
    assert ResultsHeadline.text(%{niches: 9, worth: 3}) == "Dziewięć nisz. Trzy warte zajęcia."
  end

  test "no Niche at all" do
    assert ResultsHeadline.text(%{niches: 0, worth: 0}) == "Zero nisz. Żadna nie jest warta zajęcia."
  end

  test "one Niche takes the singular" do
    assert ResultsHeadline.text(%{niches: 1, worth: 1}) == "Jedna nisza. Jedna warta zajęcia."
  end

  test "two to four Niches take the few form" do
    assert Enum.map(2..4, &ResultsHeadline.text(%{niches: &1, worth: 0})) == [
             "Dwie nisze. Żadna nie jest warta zajęcia.",
             "Trzy nisze. Żadna nie jest warta zajęcia.",
             "Cztery nisze. Żadna nie jest warta zajęcia."
           ]
  end

  test "five to twenty Niches take the many form in words" do
    assert ResultsHeadline.text(%{niches: 5, worth: 0}) =~ ~r/^Pięć nisz\. /
    assert ResultsHeadline.text(%{niches: 12, worth: 0}) =~ ~r/^Dwanaście nisz\. /
    assert ResultsHeadline.text(%{niches: 20, worth: 0}) =~ ~r/^Dwadzieścia nisz\. /
  end

  test "twenty-two Niches are digits with the few form" do
    assert ResultsHeadline.text(%{niches: 22, worth: 0}) =~ ~r/^22 nisze\. /
  end

  test "more than twenty Niches are digits" do
    assert ResultsHeadline.text(%{niches: 25, worth: 21}) == "25 nisz. 21 wartych zajęcia."
  end

  test "none worth going after says none is" do
    assert ResultsHeadline.text(%{niches: 6, worth: 0}) == "Sześć nisz. Żadna nie jest warta zajęcia."
  end

  test "one worth going after takes the singular" do
    assert ResultsHeadline.text(%{niches: 6, worth: 1}) == "Sześć nisz. Jedna warta zajęcia."
  end

  test "two to four worth going after take the few form" do
    assert Enum.map(2..4, &ResultsHeadline.text(%{niches: 6, worth: &1})) == [
             "Sześć nisz. Dwie warte zajęcia.",
             "Sześć nisz. Trzy warte zajęcia.",
             "Sześć nisz. Cztery warte zajęcia."
           ]
  end

  test "five or more worth going after take the many form" do
    assert ResultsHeadline.text(%{niches: 6, worth: 5}) == "Sześć nisz. Pięć wartych zajęcia."
    assert ResultsHeadline.text(%{niches: 14, worth: 13}) == "Czternaście nisz. Trzynaście wartych zajęcia."
  end

  test "before the Niches are scored the heading speaks of the Phrases so far" do
    assert ResultsHeadline.text(:before_scoring) == "Frazy do tej pory."
  end

  test "the status line names the best Niche and how weak its competition is" do
    best = %{name: "Rejsy po zalewie", competition: %{verdict: :weak, holders: "fora, poradniki i blogi"}}

    assert ResultsHeadline.status_line(best) ==
             "Najlepsza szansa to Rejsy po zalewie. Na pierwszej stronie przeważają słabe wyniki: fora, poradniki i blogi."
  end

  test "the status line says so when the best Niche's competition wasn't checked" do
    assert ResultsHeadline.status_line(%{name: "Rejsy po zalewie", competition: nil}) ==
             "Najlepsza szansa to Rejsy po zalewie. Konkurencji jeszcze nie sprawdziłem."
  end

  test "the status line says so when no Niche is left" do
    assert ResultsHeadline.status_line(nil) =~ "Nie została żadna nisza do wyboru."
  end
end
