defmodule Dirmoon.Research.RunsStatusLine do
  @moduledoc """
  The status sentence of the runs list ("Results"): one first-person line built from the listed runs' statuses, never by the LLM. It counts the
  runs and names those in progress, waiting for a Niche choice and failed, in
  that order. See `docs/design/README.md` section 8.2 and
  `Dirmoon.Research.StatusLine` for a single run's sentence.
  """

  alias Dirmoon.Format
  alias Dirmoon.Research.Run

  @empty_sentence "No research yet. Describe a business and I'll find its niches."

  @run_noun %{one: "research run", other: "research runs"}

  @status_clauses [
    %{status: :running, label: "in progress"},
    %{status: :awaiting_choice, label: "waiting for a niche choice"},
    %{status: :failed, label: "failed"}
  ]

  @doc """
  The sentence for the listed runs, e.g. "You have 3 research runs: 1
  waiting for a niche choice."
  """
  def sentence([]), do: @empty_sentence

  def sentence([%Run{} | _more] = runs) do
    counts = Enum.frequencies_by(runs, & &1.status)

    case status_clauses(counts) do
      [] -> "You have #{count(runs)}."
      clauses -> "You have #{count(runs)}: #{Enum.join(clauses, ", ")}."
    end
  end

  @doc """
  The number of runs with the noun that agrees with it ("3 research runs").
  """
  def count(runs) when is_list(runs) do
    number = length(runs)
    "#{number} #{Format.plural(number, @run_noun)}"
  end

  defp status_clauses(counts) do
    @status_clauses
    |> Enum.map(fn %{status: status, label: label} -> %{number: Map.get(counts, status, 0), label: label} end)
    |> Enum.reject(&(&1.number == 0))
    |> Enum.map(fn %{number: number, label: label} -> "#{number} #{label}" end)
  end
end
