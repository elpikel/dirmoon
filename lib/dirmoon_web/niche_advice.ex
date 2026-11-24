defmodule DirmoonWeb.NicheAdvice do
  @moduledoc """
  What the results screen tells a business owner about a Niche in plain
  words: a one-line verdict (is it worth going after) and the three reasons
  behind it (how many people search, what a click is worth, who answers on
  Google's first page today). Built from the Niche's Score, market totals and
  pooled competition, never by the LLM.
  """

  alias Dirmoon.Niches.Scoring
  alias Dirmoon.Polish
  alias DirmoonWeb.RunDisplay

  @labels %{
    worth: "Warto spróbować",
    hard: "Warto, ale będzie trudno",
    low: "Raczej nie warto",
    unscored: "Bez oceny"
  }

  @classes %{worth: "text-accent", hard: "text-warn", low: "text-on-app-muted", unscored: "text-on-app-muted"}

  @volume_forms %{one: "wyszukiwanie", few: "wyszukiwania", many: "wyszukiwań"}
  @time_forms %{one: "raz", few: "razy", many: "razy"}

  @competition_reasons %{
    weak:
      "Na pierwszej stronie Google są dziś głównie %{holders}, a nie oferty firm takich jak Twoja. Dobra strona ma tu szansę.",
    medium: "Pierwsza strona Google jest mieszana: %{holders}. Da się tam wejść, ale nie od razu.",
    strong: "Na pierwszej stronie Google są dziś głównie %{holders}. Przebicie się między nie zajmie czas."
  }

  @doc """
  The advice for one Niche summary (`Dirmoon.Niches.list_summaries/1`):
  `kind` is `:worth` (Score of 4 or more), `:hard` (the same with strong
  competition), `:low` (a lower Score) or `:unscored`.

  Returns `%{kind:, label:, class:, demand:, value:, competition:}`; `class`
  is the label's text colour and the last three are full sentences.
  """
  def advice(%{niche: niche, volume: volume, cpc: cpc, competition: competition}) do
    kind = kind(niche.score, competition)

    %{
      kind: kind,
      label: Map.fetch!(@labels, kind),
      class: Map.fetch!(@classes, kind),
      demand: demand(volume),
      value: value(cpc),
      competition: competition_reason(competition)
    }
  end

  @doc """
  The short figures under a Niche's name in the list: monthly searches and
  the competition verdict, e.g. "1 090 wyszukiwań / mies. · mocna konkurencja".
  """
  def figures(%{volume: volume, competition: competition}) do
    "#{Polish.integer(volume)} #{Polish.plural(volume, @volume_forms)} / mies. · #{competition_figure(competition)}"
  end

  defp kind(nil, _competition), do: :unscored

  defp kind(score, competition) do
    cond do
      not Scoring.worth?(score) -> :low
      match?(%{verdict: :strong}, competition) -> :hard
      true -> :worth
    end
  end

  defp demand(0), do: "Prawie nikt tak nie szuka: Google nie pokazuje dla tych fraz mierzalnej liczby wyszukiwań."

  defp demand(volume) do
    "Ludzie wpisują te frazy w Google około #{Polish.integer(volume)} #{Polish.plural(volume, @time_forms)} w miesiącu."
  end

  defp value(nil), do: "Nikt nie płaci za reklamy przy tych frazach, więc nie wiem, ile wart jest tu klient."

  defp value(cpc) do
    "Firmy płacą Google średnio #{Polish.usd(cpc)} za jedno kliknięcie reklamy przy tych frazach. " <>
      "Im wyższa cena, tym cenniejszy klient."
  end

  defp competition_reason(nil), do: "Nie sprawdziłem, kto jest na pierwszej stronie Google dla tych fraz."

  defp competition_reason(%{verdict: verdict, holders: holders}) do
    @competition_reasons |> Map.fetch!(verdict) |> String.replace("%{holders}", holders)
  end

  defp competition_figure(nil), do: "konkurencja niesprawdzona"

  defp competition_figure(%{verdict: verdict}),
    do: "#{verdict |> RunDisplay.verdict_label() |> String.downcase()} konkurencja"
end
