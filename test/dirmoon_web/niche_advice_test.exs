defmodule DirmoonWeb.NicheAdviceTest do
  use ExUnit.Case, async: true

  alias Dirmoon.Niches.Niche
  alias DirmoonWeb.NicheAdvice

  @no_break_space " "

  test "a Niche scoring 4 or more without strong competition is worth trying, in the accent" do
    advice =
      NicheAdvice.advice(
        summary(%{score: "4.0", competition: %{verdict: :medium, holders: "duże portale, firmy z Twojej branży"}})
      )

    assert %{kind: :worth, label: "Warto spróbować", class: "text-accent"} = advice

    assert advice.competition ==
             "Pierwsza strona Google jest mieszana: duże portale, firmy z Twojej branży. Da się tam wejść, ale nie od razu."
  end

  test "a Niche scoring 4 or more against strong competition is worth it but hard, in the warning colour" do
    advice =
      NicheAdvice.advice(
        summary(%{score: "8.1", competition: %{verdict: :strong, holders: "firmy z Twojej branży, duże portale"}})
      )

    assert %{kind: :hard, label: "Warto, ale będzie trudno", class: "text-warn"} = advice

    assert advice.competition ==
             "Na pierwszej stronie Google są dziś głównie firmy z Twojej branży, duże portale. Przebicie się między nie zajmie czas."
  end

  test "a Niche scoring under 4 is rather not worth it, whatever its competition" do
    advice =
      NicheAdvice.advice(summary(%{score: "3.9", competition: %{verdict: :weak, holders: "katalogi firm, duże portale"}}))

    assert %{kind: :low, label: "Raczej nie warto", class: "text-on-app-muted"} = advice

    assert advice.competition ==
             "Na pierwszej stronie Google są dziś głównie katalogi firm, duże portale, a nie oferty firm takich jak Twoja. Dobra strona ma tu szansę."
  end

  test "an unscored Niche has no verdict" do
    assert %{kind: :unscored, label: "Bez oceny", class: "text-on-app-muted"} =
             NicheAdvice.advice(summary(%{score: nil}))
  end

  test "the demand reason gives the monthly searches, or says nobody searches" do
    assert NicheAdvice.advice(summary(%{volume: 1_090})).demand ==
             "Ludzie wpisują te frazy w Google około 1#{@no_break_space}090 razy w miesiącu."

    assert NicheAdvice.advice(summary(%{volume: 1})).demand == "Ludzie wpisują te frazy w Google około 1 raz w miesiącu."

    assert NicheAdvice.advice(summary(%{volume: 0})).demand ==
             "Prawie nikt tak nie szuka: Google nie pokazuje dla tych fraz mierzalnej liczby wyszukiwań."
  end

  test "the value reason gives the price of a click, or says nobody advertises" do
    assert NicheAdvice.advice(summary(%{cpc: Decimal.new("6.79")})).value ==
             "Firmy płacą Google średnio $6,79 za jedno kliknięcie reklamy przy tych frazach. Im wyższa cena, tym cenniejszy klient."

    assert NicheAdvice.advice(summary(%{cpc: nil})).value ==
             "Nikt nie płaci za reklamy przy tych frazach, więc nie wiem, ile wart jest tu klient."
  end

  test "the competition reason says so when no Phrase was checked" do
    assert NicheAdvice.advice(summary(%{competition: nil})).competition ==
             "Nie sprawdziłem, kto jest na pierwszej stronie Google dla tych fraz."
  end

  test "the list figures give the monthly searches in the right plural and the competition verdict" do
    strong = %{verdict: :strong, holders: "firmy z Twojej branży"}

    assert NicheAdvice.figures(summary(%{volume: 1_090, competition: strong})) ==
             "1#{@no_break_space}090 wyszukiwań / mies. · mocna konkurencja"

    assert NicheAdvice.figures(summary(%{volume: 1, competition: nil})) ==
             "1 wyszukiwanie / mies. · konkurencja niesprawdzona"

    assert NicheAdvice.figures(summary(%{volume: 22, competition: %{verdict: :weak, holders: "poradniki i blogi"}})) ==
             "22 wyszukiwania / mies. · słaba konkurencja"
  end

  defp summary(attrs) do
    attrs = Map.merge(%{score: "5.0", volume: 100, cpc: Decimal.new("1.00"), competition: nil}, attrs)

    %{
      niche: %Niche{score: attrs.score && Decimal.new(attrs.score)},
      volume: attrs.volume,
      cpc: attrs.cpc,
      competition: attrs.competition
    }
  end
end
