defmodule DirmoonWeb.ResultsHeadlineTest do
  use ExUnit.Case, async: true

  alias DirmoonWeb.ResultsHeadline

  doctest ResultsHeadline

  test "nine Niches of which three are worth going after" do
    assert ResultsHeadline.text(%{niches: 9, worth: 3}) == %{lead: "Dziewięć nisz.", underline: "Trzy warte zajęcia."}
  end

  test "no Niche at all" do
    assert ResultsHeadline.text(%{niches: 0, worth: 0}) ==
             %{lead: "Zero nisz.", underline: "Żadna nie jest warta zajęcia."}
  end

  test "one Niche takes the singular" do
    assert ResultsHeadline.text(%{niches: 1, worth: 1}) == %{lead: "Jedna nisza.", underline: "Jedna warta zajęcia."}
  end

  test "two to four Niches take the few form" do
    assert Enum.map(2..4, &ResultsHeadline.text(%{niches: &1, worth: 0}).lead) ==
             ["Dwie nisze.", "Trzy nisze.", "Cztery nisze."]
  end

  test "five to twenty Niches take the many form in words" do
    assert ResultsHeadline.text(%{niches: 5, worth: 0}).lead == "Pięć nisz."
    assert ResultsHeadline.text(%{niches: 12, worth: 0}).lead == "Dwanaście nisz."
    assert ResultsHeadline.text(%{niches: 20, worth: 0}).lead == "Dwadzieścia nisz."
  end

  test "twenty-two Niches are digits with the few form" do
    assert ResultsHeadline.text(%{niches: 22, worth: 0}).lead == "22 nisze."
  end

  test "more than twenty Niches are digits" do
    assert ResultsHeadline.text(%{niches: 25, worth: 21}) == %{lead: "25 nisz.", underline: "21 wartych zajęcia."}
  end

  test "none worth going after says none is" do
    assert ResultsHeadline.text(%{niches: 6, worth: 0}).underline == "Żadna nie jest warta zajęcia."
  end

  test "one worth going after takes the singular" do
    assert ResultsHeadline.text(%{niches: 6, worth: 1}).underline == "Jedna warta zajęcia."
  end

  test "two to four worth going after take the few form" do
    assert Enum.map(2..4, &ResultsHeadline.text(%{niches: 6, worth: &1}).underline) ==
             ["Dwie warte zajęcia.", "Trzy warte zajęcia.", "Cztery warte zajęcia."]
  end

  test "five or more worth going after take the many form" do
    assert ResultsHeadline.text(%{niches: 6, worth: 5}).underline == "Pięć wartych zajęcia."
    assert ResultsHeadline.text(%{niches: 14, worth: 13}).underline == "Trzynaście wartych zajęcia."
  end

  test "before the Niches are scored the headline speaks of the Phrases so far" do
    assert ResultsHeadline.text(:before_scoring) == %{lead: "Frazy", underline: "do tej pory."}
  end

  test "the status line names the best Niche and how weak its competition is" do
    best = %{name: "Rejsy po zalewie", competition: %{verdict: :weak, holders: "fora, blogi"}}

    assert ResultsHeadline.status_line(best) ==
             "Najlepsza szansa to Rejsy po zalewie. Na pierwszej stronie przeważają słabe wyniki: fora, blogi."
  end

  test "the status line says so when the best Niche's competition wasn't checked" do
    assert ResultsHeadline.status_line(%{name: "Rejsy po zalewie", competition: nil}) ==
             "Najlepsza szansa to Rejsy po zalewie. Konkurencji jeszcze nie sprawdziłem."
  end

  test "the status line says so when no Niche is left" do
    assert ResultsHeadline.status_line(nil) =~ "Nie została żadna nisza do wyboru."
  end

  test "a Niche's competition line has the verdict and who holds the top 10" do
    assert ResultsHeadline.competition_line(%{verdict: :strong, holders: "konkurenci, portale"}) ==
             "Mocna konkurencja: konkurenci, portale"

    assert ResultsHeadline.competition_line(nil) == "Konkurencja niesprawdzona"
  end
end
