defmodule Dirmoon.Niches.ScoreStep do
  @moduledoc """
  Step 7: scores the run's proposed Niches (`Dirmoon.Niches.Scoring`) on
  their Volume, CPC and competition, with the weights from
  `config :dirmoon, scoring_weights:`, and stores the Scores. Scoring again
  recomputes and overwrites them, so a re-run gives the same Scores.
  """

  alias Dirmoon.Format
  alias Dirmoon.Niches
  alias Dirmoon.Niches.Scoring
  alias Dirmoon.Research.Run

  @no_niches_error "No niches to score"
  @scored_forms %{one: "niche scored", other: "niches scored"}
  @worth_forms %{one: "worth going after", other: "worth going after"}

  @doc """
  Returns `{:ok, %{result: "9 niches scored, 3 worth going after", output: %{"niches" => 9, "worth" => 3, "weights" => %{"volume" => 0.4, "cpc" => 0.3, "weakness" => 0.3}}}}`
  or `{:error, "#{@no_niches_error}"}`.
  """
  def score(%Run{} = run) do
    weights = Application.fetch_env!(:dirmoon, :scoring_weights)

    with {:ok, aggregates} <- aggregates(run),
         scores = Scoring.score(aggregates, weights),
         {:ok, scored} <- Niches.store_scores(run, scores) do
      worth = Enum.count(scores, &Scoring.worth?(&1.score))

      {:ok,
       %{
         result: result_line(scored, worth),
         output: %{
           "niches" => scored,
           "worth" => worth,
           "weights" => Map.new(weights, fn {name, weight} -> {Atom.to_string(name), weight} end)
         }
       }}
    end
  end

  defp aggregates(run) do
    case Niches.niche_aggregates(run) do
      [] -> {:error, @no_niches_error}
      aggregates -> {:ok, aggregates}
    end
  end

  defp result_line(scored, worth) do
    "#{scored} #{Format.plural(scored, @scored_forms)}, #{worth} #{Format.plural(worth, @worth_forms)}"
  end
end
