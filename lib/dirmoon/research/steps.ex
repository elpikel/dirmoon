defmodule Dirmoon.Research.Steps do
  @moduledoc """
  The eight Steps of a Research Run as data: number, key, name, the
  Oban worker that runs it, the Modes it applies to, and whether it follows
  the previous Step on its own (Steps 1–7) or waits for the user (8).
  """

  @all_modes [:new_idea, :existing_site]

  @steps [
    %{
      number: 1,
      key: :seeds,
      name: "Starting ideas",
      worker: Dirmoon.Workers.GenerateSeeds,
      modes: @all_modes,
      auto_chained?: true
    },
    %{
      number: 2,
      key: :expansion,
      name: "Real searches",
      worker: Dirmoon.Workers.ExpandPhrases,
      modes: @all_modes,
      auto_chained?: true
    },
    %{
      number: 3,
      key: :volumes,
      name: "How often people search",
      worker: Dirmoon.Workers.FetchVolumes,
      modes: @all_modes,
      auto_chained?: true
    },
    %{
      number: 4,
      key: :filter_and_group,
      name: "Topics",
      worker: Dirmoon.Workers.FilterAndGroup,
      modes: @all_modes,
      auto_chained?: true
    },
    %{
      number: 5,
      key: :competition,
      name: "Google's first page",
      worker: Dirmoon.Workers.CheckCompetition,
      modes: @all_modes,
      auto_chained?: true
    },
    %{
      number: 6,
      key: :current_positions,
      name: "Where your site shows up",
      worker: Dirmoon.Workers.FetchCurrentPositions,
      modes: [:existing_site],
      skipped_result: "New idea, no site yet",
      auto_chained?: true
    },
    %{
      number: 7,
      key: :scoring,
      name: "Rating",
      worker: Dirmoon.Workers.ScoreNiches,
      modes: @all_modes,
      auto_chained?: true
    },
    %{
      number: 8,
      key: :brief,
      name: "Brief",
      worker: Dirmoon.Workers.WriteBrief,
      modes: @all_modes,
      auto_chained?: false
    }
  ]

  @numbers Enum.map(@steps, & &1.number)
  @numbers_by_key Map.new(@steps, &{&1.key, &1.number})

  def all, do: @steps

  def numbers, do: @numbers

  def get!(number) when number in @numbers do
    Enum.find(@steps, &(&1.number == number))
  end

  @doc """
  The number of the Step with the given key (`:competition` → 5). Raises for
  an unknown key.
  """
  def number!(key), do: Map.fetch!(@numbers_by_key, key)

  def auto_chained?(number), do: get!(number).auto_chained?

  def applies?(%{modes: modes}, mode), do: mode in modes
end
