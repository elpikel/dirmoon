defmodule Dirmoon.Niches.ScoringTest do
  use ExUnit.Case, async: true

  alias Dirmoon.Niches.Scoring

  @weights %{volume: 0.4, cpc: 0.3, weakness: 0.3}

  test "volume and cpc are log-normalised within the run and weighted with weakness into a 0–10 score" do
    aggregates = [
      %{niche_id: 1, volume: 99, cpc: Decimal.new("9"), weak_share: 1.0},
      %{niche_id: 2, volume: 9, cpc: nil, weak_share: 0.5},
      %{niche_id: 3, volume: 0, cpc: Decimal.new("3"), weak_share: nil}
    ]

    scores = aggregates |> Scoring.score(@weights) |> Map.new(&{&1.niche_id, &1})

    # Niche 1 holds the run's highest volume (99) and cpc (9):
    # volume = log1p(99) / log1p(99) = 1, cpc = log1p(9) / log1p(9) = 1, weakness = 1.0
    # score = 10 × (0.4 × 1 + 0.3 × 1 + 0.3 × 1.0) = 10.0
    assert Decimal.to_string(scores[1].score) == "10.0"
    assert rounded(scores[1].components) == %{"volume" => 1.0, "cpc" => 1.0, "weakness" => 1.0}

    # Niche 2: volume = log1p(9) / log1p(99) = ln 10 / ln 100 = 0.5, cpc nil counts as 0, weakness = 0.5
    # score = 10 × (0.4 × 0.5 + 0.3 × 0 + 0.3 × 0.5) = 3.5
    assert Decimal.to_string(scores[2].score) == "3.5"
    assert rounded(scores[2].components) == %{"volume" => 0.5, "cpc" => 0.0, "weakness" => 0.5}

    # Niche 3: volume = 0, cpc = log1p(3) / log1p(9) = ln 4 / ln 10 ≈ 0.60206, no SERP check so weakness = 0.5
    # score = 10 × (0.4 × 0 + 0.3 × 0.60206 + 0.3 × 0.5) ≈ 3.306 → 3.3
    assert Decimal.to_string(scores[3].score) == "3.3"
    assert rounded(scores[3].components) == %{"volume" => 0.0, "cpc" => 0.60206, "weakness" => 0.5}
  end

  test "a run with a single niche gets the full volume and cpc components" do
    [score] = Scoring.score([%{niche_id: 7, volume: 37, cpc: Decimal.new("1.37"), weak_share: 0.0}], @weights)

    # score = 10 × (0.4 × 1 + 0.3 × 1 + 0.3 × 0.0) = 7.0
    assert score.niche_id == 7
    assert Decimal.to_string(score.score) == "7.0"
    assert rounded(score.components) == %{"volume" => 1.0, "cpc" => 1.0, "weakness" => 0.0}
  end

  test "when every niche has zero volume the volume component is 0 for all of them" do
    scores =
      Scoring.score(
        [
          %{niche_id: 1, volume: 0, cpc: Decimal.new("2"), weak_share: 0.0},
          %{niche_id: 2, volume: 0, cpc: Decimal.new("2"), weak_share: 0.0}
        ],
        @weights
      )

    # score = 10 × (0.4 × 0 + 0.3 × 1 + 0.3 × 0.0) = 3.0
    assert Enum.map(scores, & &1.components["volume"]) == [0.0, 0.0]
    assert Enum.map(scores, &Decimal.to_string(&1.score)) == ["3.0", "3.0"]
  end

  test "when no niche has a cpc the cpc component is 0 for all of them" do
    scores =
      Scoring.score(
        [
          %{niche_id: 1, volume: 15, cpc: nil, weak_share: 0.0},
          %{niche_id: 2, volume: 15, cpc: Decimal.new("0"), weak_share: 0.0}
        ],
        @weights
      )

    # score = 10 × (0.4 × 1 + 0.3 × 0 + 0.3 × 0.0) = 4.0
    assert Enum.map(scores, & &1.components["cpc"]) == [0.0, 0.0]
    assert Enum.map(scores, &Decimal.to_string(&1.score)) == ["4.0", "4.0"]
  end

  test "a niche without a checked phrase gets the neutral weakness of 0.5" do
    [score] = Scoring.score([%{niche_id: 1, volume: 0, cpc: nil, weak_share: nil}], @weights)

    # score = 10 × (0.4 × 0 + 0.3 × 0 + 0.3 × 0.5) = 1.5
    assert score.components["weakness"] == 0.5
    assert Decimal.to_string(score.score) == "1.5"
  end

  test "a niche with nothing going for it scores 0" do
    [score] = Scoring.score([%{niche_id: 1, volume: 0, cpc: nil, weak_share: 0.0}], @weights)

    assert Decimal.to_string(score.score) == "0.0"
  end

  test "the score is rounded to one decimal" do
    [score] = Scoring.score([%{niche_id: 1, volume: 12, cpc: Decimal.new("0.4"), weak_share: 0.123}], @weights)

    # score = 10 × (0.4 × 1 + 0.3 × 1 + 0.3 × 0.123) = 7.369 → 7.4
    assert Decimal.to_string(score.score) == "7.4"
  end

  test "weights just above 1 within the tolerance never push the score above 10" do
    [score] =
      Scoring.score(
        [%{niche_id: 1, volume: 5, cpc: Decimal.new("1"), weak_share: 1.0}],
        %{volume: 0.409, cpc: 0.3, weakness: 0.3}
      )

    assert Decimal.to_string(score.score) == "10.0"
  end

  test "weights that do not sum to 1 are refused" do
    assert_raise ArgumentError, fn ->
      Scoring.score([%{niche_id: 1, volume: 5, cpc: nil, weak_share: nil}], %{volume: 0.5, cpc: 0.3, weakness: 0.3})
    end
  end

  test "no niches give no scores" do
    assert Scoring.score([], @weights) == []
  end

  test "a niche is worth going after from a score of 4" do
    refute Scoring.worth?(Decimal.new("3.9"))
    assert Scoring.worth?(Decimal.new("4.0"))
    assert Scoring.worth?(Decimal.new("8.1"))
    refute Scoring.worth?(nil)
  end

  defp rounded(components), do: Map.new(components, fn {name, value} -> {name, Float.round(value, 5)} end)
end
