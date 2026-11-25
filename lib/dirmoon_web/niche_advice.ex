defmodule DirmoonWeb.NicheAdvice do
  @moduledoc """
  What the results screen tells a business owner about a Niche in plain
  words: a one-line verdict (is it worth going after) and the three reasons
  behind it (how many people search, what an ad click is worth, who answers on
  Google's first page today). Built from the Niche's Score, market totals and
  pooled competition, never by the LLM.
  """

  alias Dirmoon.Format
  alias Dirmoon.Niches.Scoring
  alias DirmoonWeb.RunDisplay

  @labels %{
    worth: "Worth a try",
    hard: "Worth it, but hard",
    low: "Probably not worth it",
    unscored: "Not rated yet"
  }

  @classes %{worth: "text-accent", hard: "text-warn", low: "text-on-app-muted", unscored: "text-on-app-muted"}

  @time_forms %{one: "time", other: "times"}

  @competition_reasons %{
    weak:
      "Weak competition: Google's first page today holds mostly %{holders}, not offers from businesses like yours. " <>
        "A good page can get onto it.",
    medium:
      "Medium competition: Google's first page is a mix of %{holders}. Getting onto it is possible, but not at once.",
    strong:
      "Strong competition: Google's first page today holds mostly %{holders}. Getting onto it will be hard and slow."
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
  The short figures under a Niche's name in the list: how many times a month
  people type its Phrases and the competition verdict with what it means, e.g.
  "Typed 1,090 times a month · strong competition, hard to get onto Google's first page".
  """
  def figures(%{volume: volume, competition: competition}) do
    "Typed #{Format.integer(volume)} #{Format.plural(volume, @time_forms)} a month · #{competition_figure(competition)}"
  end

  defp kind(nil, _competition), do: :unscored

  defp kind(score, competition) do
    cond do
      not Scoring.worth?(score) -> :low
      match?(%{verdict: :strong}, competition) -> :hard
      true -> :worth
    end
  end

  defp demand(0), do: "Almost nobody types these into Google: Google can't measure even one search a month."

  defp demand(volume) do
    "People type these searches into Google about #{Format.integer(volume)} #{Format.plural(volume, @time_forms)} a month."
  end

  defp value(nil), do: "Nobody pays Google for ads on these searches, so I can't tell what a customer is worth here."

  defp value(cpc) do
    "Businesses pay Google #{Format.usd(cpc)} on average for one ad click on these searches. " <>
      "The higher the price, the more a customer is worth."
  end

  defp competition_reason(nil), do: "I haven't checked who is on Google's first page for these searches."

  defp competition_reason(%{verdict: verdict, holders: holders}) do
    @competition_reasons |> Map.fetch!(verdict) |> String.replace("%{holders}", holders)
  end

  defp competition_figure(nil), do: "competition not checked yet"

  defp competition_figure(%{verdict: verdict}) do
    "#{verdict |> RunDisplay.verdict_label() |> String.downcase()} competition, #{RunDisplay.verdict_meaning(verdict)}"
  end
end
