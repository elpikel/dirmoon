defmodule Dirmoon.Niches.Scoring do
  @moduledoc """
  The Score of a run's Niches, as pure maths (no Repo):

      Score = 10 × (w_volume × volume + w_cpc × cpc + w_weakness × weakness)

  `volume` and `cpc` are `log1p`-normalised to 0–1 against the run's highest
  value; `weakness` is the share of the Niche's checked top-10 results held by
  blogs, forums and directories, or the neutral 0.5 when none of its
  Phrases was checked. A Niche is worth going after from a Score of
  4 (`worth_threshold/0`).
  """

  @neutral_weakness 0.5
  @worth_threshold Decimal.new("4")
  @weights_tolerance 0.01
  @max_score 10.0

  @doc """
  Scores every Niche of a run. `aggregates` are
  `%{niche_id:, volume: non_neg_integer, cpc: Decimal | nil, weak_share: float | nil}`;
  `weights` is `%{volume:, cpc:, weakness:}` summing to 1 (otherwise an
  `ArgumentError`).

  Returns `[%{niche_id:, score: Decimal (0–10, one decimal), components: %{"volume", "cpc", "weakness"}}]`
  in the order of `aggregates`.
  """
  def score(aggregates, %{volume: _volume, cpc: _cpc, weakness: _weakness} = weights) when is_list(aggregates) do
    validate_weights!(weights)

    max_volume = aggregates |> Enum.map(& &1.volume) |> Enum.max(fn -> 0 end)
    max_cpc = aggregates |> Enum.map(&cpc_value(&1.cpc)) |> Enum.max(fn -> 0.0 end)

    Enum.map(aggregates, fn aggregate ->
      components = %{
        "volume" => normalised(aggregate.volume, max_volume),
        "cpc" => normalised(cpc_value(aggregate.cpc), max_cpc),
        "weakness" => weakness(aggregate.weak_share)
      }

      %{niche_id: aggregate.niche_id, score: weighted_score(components, weights), components: components}
    end)
  end

  @doc "The Score from which a Niche is worth going after."
  def worth_threshold, do: @worth_threshold

  @doc "Whether a Score makes its Niche worth going after; an unscored Niche never is."
  def worth?(nil), do: false
  def worth?(%Decimal{} = score), do: Decimal.compare(score, @worth_threshold) != :lt

  defp validate_weights!(%{volume: volume, cpc: cpc, weakness: weakness} = weights) do
    if abs(volume + cpc + weakness - 1.0) > @weights_tolerance do
      raise ArgumentError, "scoring weights must sum to 1, got: #{inspect(weights)}"
    end
  end

  defp cpc_value(nil), do: 0.0
  defp cpc_value(%Decimal{} = cpc), do: Decimal.to_float(cpc)

  defp normalised(_value, max_value) when max_value <= 0, do: 0.0
  defp normalised(value, max_value), do: :math.log(1 + value) / :math.log(1 + max_value)

  defp weakness(nil), do: @neutral_weakness
  defp weakness(weak_share) when is_float(weak_share), do: weak_share

  defp weighted_score(components, weights) do
    weighted_sum =
      weights.volume * components["volume"] + weights.cpc * components["cpc"] +
        weights.weakness * components["weakness"]

    (10 * weighted_sum)
    |> min(@max_score)
    |> max(0.0)
    |> Decimal.from_float()
    |> Decimal.round(1)
  end
end
