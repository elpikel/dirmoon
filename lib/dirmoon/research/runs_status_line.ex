defmodule Dirmoon.Research.RunsStatusLine do
  @moduledoc """
  The status sentence of the runs list ("Wyniki"): one first-person Polish
  line built from the listed runs' statuses, never by the LLM. It counts the
  runs and names those in progress, waiting for a Niche choice and failed, in
  that order. See `docs/design/README.md` section 8.2 and
  `Dirmoon.Research.StatusLine` for a single run's sentence.
  """

  alias Dirmoon.Polish
  alias Dirmoon.Research.Run

  @empty_sentence "Nie mam jeszcze żadnego researchu. Opisz biznes, a znajdę nisze."

  @run_noun %{one: "research", few: "researche", many: "researchy"}

  @status_clauses [
    %{status: :running, forms: %{one: "w toku", few: "w toku", many: "w toku"}},
    %{
      status: :awaiting_choice,
      forms: %{one: "czeka na wybór niszy", few: "czekają na wybór niszy", many: "czeka na wybór niszy"}
    },
    %{status: :failed, forms: %{one: "z błędem", few: "z błędem", many: "z błędem"}}
  ]

  @doc """
  The sentence for the listed runs, e.g. "Masz 3 researche: 1 czeka na wybór
  niszy."
  """
  def sentence([]), do: @empty_sentence

  def sentence([%Run{} | _more] = runs) do
    counts = Enum.frequencies_by(runs, & &1.status)

    case status_clauses(counts) do
      [] -> "Masz #{count(runs)}."
      clauses -> "Masz #{count(runs)}: #{Enum.join(clauses, ", ")}."
    end
  end

  @doc """
  The number of runs with the noun that agrees with it ("3 researche").
  """
  def count(runs) when is_list(runs) do
    number = length(runs)
    "#{number} #{Polish.plural(number, @run_noun)}"
  end

  defp status_clauses(counts) do
    @status_clauses
    |> Enum.map(fn %{status: status, forms: forms} -> %{number: Map.get(counts, status, 0), forms: forms} end)
    |> Enum.reject(&(&1.number == 0))
    |> Enum.map(fn %{number: number, forms: forms} -> "#{number} #{Polish.plural(number, forms)}" end)
  end
end
