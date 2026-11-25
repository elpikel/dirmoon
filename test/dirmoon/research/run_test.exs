defmodule Dirmoon.Research.RunTest do
  use Dirmoon.DataCase, async: true

  alias Dirmoon.Research.Run

  test "results are ready once Step 7 is done" do
    run = build(:run, status: :awaiting_choice, steps: build_run_steps(Map.new(1..7, &{&1, :done})))

    assert Run.results_ready?(run)
  end

  test "results stay ready while a Brief is written or after Step 8 failed" do
    after_scoring = Map.new(1..7, &{&1, :done})
    writing = build(:run, status: :running, steps: after_scoring |> Map.put(8, :running) |> build_run_steps())
    failed = build(:run, status: :failed, steps: after_scoring |> Map.put(8, :failed) |> build_run_steps())

    assert Run.results_ready?(writing)
    assert Run.results_ready?(failed)
  end

  test "results aren't ready before Step 7 is done" do
    running =
      build(:run, status: :running, steps: 1..6 |> Map.new(&{&1, :done}) |> Map.put(7, :running) |> build_run_steps())

    failed = build(:run, status: :failed, steps: build_run_steps(%{1 => :done, 2 => :done, 3 => :failed}))

    refute Run.results_ready?(running)
    refute Run.results_ready?(failed)
  end

  test "a Niche can be chosen once results are ready and the run isn't stopped" do
    after_scoring = build_run_steps(Map.new(1..7, &{&1, :done}))
    awaiting = build(:run, status: :awaiting_choice, steps: after_scoring)
    stopped = build(:run, status: :stopped, steps: after_scoring)

    before_scoring =
      build(:run, status: :running, steps: 1..6 |> Map.new(&{&1, :done}) |> Map.put(7, :running) |> build_run_steps())

    assert Run.choosable?(awaiting)
    refute Run.choosable?(stopped)
    refute Run.choosable?(before_scoring)
  end
end
