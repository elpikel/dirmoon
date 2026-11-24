defmodule Dirmoon.Research.RunsStatusLineTest do
  use ExUnit.Case, async: true

  import Dirmoon.Factory

  alias Dirmoon.Research.RunsStatusLine

  test "with no runs it says there is no research yet and invites a description" do
    assert RunsStatusLine.sentence([]) == "Nie mam jeszcze żadnego researchu. Opisz biznes, a znajdę nisze."
  end

  test "it counts the runs and says how many wait for a niche choice" do
    runs = [build(:run, status: :done), build(:run, status: :awaiting_choice), build(:run, status: :done)]

    assert RunsStatusLine.sentence(runs) == "Masz 3 researche: 1 czeka na wybór niszy."
  end

  test "it names the runs in progress, waiting for a choice and failed, in that order" do
    runs = [
      build(:run, status: :failed),
      build(:run, status: :awaiting_choice),
      build(:run, status: :awaiting_choice),
      build(:run, status: :running)
    ]

    assert RunsStatusLine.sentence(runs) == "Masz 4 researche: 1 w toku, 2 czekają na wybór niszy, 1 z błędem."
  end

  test "runs that need nothing from the User are only counted" do
    runs =
      [build(:run, status: :done), build(:run, status: :stopped)] ++
        Enum.map(1..3, fn _index -> build(:run, status: :done) end)

    assert RunsStatusLine.sentence(runs) == "Masz 5 researchy."
  end

  test "a single run is counted in the singular" do
    assert RunsStatusLine.sentence([build(:run, status: :done)]) == "Masz 1 research."
  end

  test "the count of runs agrees with the Polish plural" do
    assert RunsStatusLine.count([build(:run), build(:run)]) == "2 researche"
    assert RunsStatusLine.count([build(:run)]) == "1 research"
    assert RunsStatusLine.count([]) == "0 researchy"
  end
end
