defmodule DirmoonWeb.ResultsHeadline do
  @moduledoc """
  The words of the results screen, built from counts and data, never by
  the LLM: the heading stating the outcome ("Nine topics. Three worth
  going after.") above the Niche list, and the first-person status sentence
  about the best Niche.
  See `docs/design/README.md` section 8.3, screen 3.
  """

  alias Dirmoon.Format

  @niche_forms %{one: "topic", other: "topics"}
  @worth_suffix "worth going after."
  @before_scoring "What people type into Google, so far."

  @verdict_sentences %{
    weak: "Weak competition: easy to get onto Google's first page, which holds mostly %{holders}.",
    medium:
      "Medium competition: Google's first page is a mix of %{holders}, so getting onto it is possible, but not at once.",
    strong: "Strong competition: hard to get onto Google's first page, which holds mostly %{holders}."
  }

  @doc """
  The heading from the number of Niches on offer and of those worth going
  after, two sentences; counts up to twenty are words, larger ones digits.
  `:before_scoring` is the heading of a run whose Niches aren't scored yet.

      iex> DirmoonWeb.ResultsHeadline.text(%{niches: 9, worth: 3})
      "Nine topics. Three worth going after."
  """
  def text(:before_scoring), do: @before_scoring

  def text(%{niches: niches, worth: worth}) when is_integer(niches) and is_integer(worth) do
    "#{count_word(niches)} #{Format.plural(niches, @niche_forms)}. #{worth_sentence(worth)}"
  end

  @doc """
  The status sentence about the best Niche on offer (`nil` when none is
  left): its name and what its competition looks like, from its pooled
  verdict and who holds the top 10.
  """
  def status_line(nil), do: "No topic is left to choose. Every search is in the other views."

  def status_line(%{name: name, competition: nil}) do
    "The best chance is #{name}. I haven't checked who is on Google's first page yet."
  end

  def status_line(%{name: name, competition: %{verdict: verdict, holders: holders}}) do
    verdict_sentence = @verdict_sentences |> Map.fetch!(verdict) |> String.replace("%{holders}", holders)
    "The best chance is #{name}. #{verdict_sentence}"
  end

  defp worth_sentence(0), do: "None " <> @worth_suffix
  defp worth_sentence(worth), do: "#{count_word(worth)} #{@worth_suffix}"

  defp count_word(count) do
    count
    |> Format.number_word()
    |> String.capitalize()
  end
end
