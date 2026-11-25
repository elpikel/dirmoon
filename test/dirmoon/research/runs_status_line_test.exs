defmodule Dirmoon.Research.RunsStatusLineTest do
  use ExUnit.Case, async: true

  import Dirmoon.Factory

  alias Dirmoon.Research.RunsStatusLine

  test "with no runs it says there is no research yet and invites a description" do
    assert RunsStatusLine.sentence([]) == "No research yet. Describe a business and I'll find what its customers want."
  end

  test "it counts the runs and says how many wait for a niche choice" do
    runs = [build(:run, status: :stopped), build(:run, status: :awaiting_choice), build(:run, status: :stopped)]

    assert RunsStatusLine.sentence(runs) == "You have 3 research runs: 1 waiting for you to choose a topic."
  end

  test "it names the runs in progress, waiting for a choice and failed, in that order" do
    runs = [
      build(:run, status: :failed),
      build(:run, status: :awaiting_choice),
      build(:run, status: :awaiting_choice),
      build(:run, status: :running)
    ]

    assert RunsStatusLine.sentence(runs) ==
             "You have 4 research runs: 1 in progress, 2 waiting for you to choose a topic, 1 failed."
  end

  test "runs that need nothing from the User are only counted" do
    runs =
      [build(:run, status: :stopped), build(:run, status: :stopped)] ++
        Enum.map(1..3, fn _index -> build(:run, status: :stopped) end)

    assert RunsStatusLine.sentence(runs) == "You have 5 research runs."
  end

  test "a single run is counted in the singular" do
    assert RunsStatusLine.sentence([build(:run, status: :stopped)]) == "You have 1 research run."
  end

  test "the count of runs agrees with its number" do
    assert RunsStatusLine.count([build(:run), build(:run)]) == "2 research runs"
    assert RunsStatusLine.count([build(:run)]) == "1 research run"
    assert RunsStatusLine.count([]) == "0 research runs"
  end
end
