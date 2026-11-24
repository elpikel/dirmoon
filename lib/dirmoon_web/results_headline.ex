defmodule DirmoonWeb.ResultsHeadline do
  @moduledoc """
  The words of the results screen, built from counts and data, never by
  the LLM: the heading stating the outcome ("Dziewięć nisz. Trzy warte
  zajęcia.") above the Niche list, and the first-person status sentence
  about the best Niche.
  See `docs/design/README.md` section 8.3, screen 3.
  """

  alias Dirmoon.Polish
  alias DirmoonWeb.RunDisplay

  @niche_forms %{one: "nisza", few: "nisze", many: "nisz"}
  @worth_forms %{one: "warta", few: "warte", many: "wartych"}
  @worth_suffix "zajęcia."
  @before_scoring "Frazy do tej pory."

  @verdict_sentences %{
    weak: "Na pierwszej stronie przeważają słabe wyniki: %{holders}.",
    medium: "Konkurencja jest średnia: %{holders}.",
    strong: "Konkurencja jest mocna: %{holders}."
  }

  @doc """
  The heading from the number of Niches on offer and of those worth going
  after, two sentences; counts up to twenty are words, larger ones digits.
  `:before_scoring` is the heading of a run whose Niches aren't scored yet.

      iex> DirmoonWeb.ResultsHeadline.text(%{niches: 9, worth: 3})
      "Dziewięć nisz. Trzy warte zajęcia."
  """
  def text(:before_scoring), do: @before_scoring

  def text(%{niches: niches, worth: worth}) when is_integer(niches) and is_integer(worth) do
    "#{count_word(niches)} #{Polish.plural(niches, @niche_forms)}. #{worth_sentence(worth)}"
  end

  @doc """
  The status sentence about the best Niche on offer (`nil` when none is
  left): its name and what its competition looks like, from its pooled
  verdict and who holds the top 10.
  """
  def status_line(nil), do: "Nie została żadna nisza do wyboru. Wszystkie frazy są w widoku obok."

  def status_line(%{name: name, competition: nil}) do
    "Najlepsza szansa to #{name}. Konkurencji jeszcze nie sprawdziłem."
  end

  def status_line(%{name: name, competition: %{verdict: verdict, holders: holders}}) do
    verdict_sentence = @verdict_sentences |> Map.fetch!(verdict) |> String.replace("%{holders}", holders)
    "Najlepsza szansa to #{name}. #{verdict_sentence}"
  end

  @doc """
  One line about a Niche's competition: "Słaba konkurencja: blogi, fora",
  or that it wasn't checked.
  """
  def competition_line(nil), do: "Konkurencja niesprawdzona"

  def competition_line(%{verdict: verdict, holders: holders}) do
    "#{RunDisplay.verdict_label(verdict)} konkurencja: #{holders}"
  end

  defp worth_sentence(0), do: "Żadna nie jest warta " <> @worth_suffix
  defp worth_sentence(worth), do: "#{count_word(worth)} #{Polish.plural(worth, @worth_forms)} #{@worth_suffix}"

  defp count_word(count) do
    count
    |> Polish.feminine_number()
    |> String.capitalize()
  end
end
