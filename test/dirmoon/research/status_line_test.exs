defmodule Dirmoon.Research.StatusLineTest do
  use ExUnit.Case, async: true

  import Dirmoon.Factory

  alias Dirmoon.Research.StatusLine

  test "a run working on Step 1 says it turns the description into seed phrases and questions" do
    run = build(:run, status: :running, steps: build_run_steps(%{1 => :running}))

    assert StatusLine.sentence(%{run: run, progress: nil}) ==
             "I'm turning the description into starting searches and customer questions."
  end

  test "a run working on Step 2 says it expands the seeds into what people type" do
    run = build(:run, status: :running, steps: build_run_steps(%{1 => :done, 2 => :running}))

    assert StatusLine.sentence(%{run: run, progress: nil}) ==
             "I'm looking up what people really type into Google, starting from those ideas."
  end

  test "a run working on Step 3 says it checks volumes and CPC" do
    run = build(:run, status: :running, steps: build_run_steps(done_through(2, %{3 => :running})))

    assert StatusLine.sentence(%{run: run, progress: nil}) ==
             "I'm checking how many times a month people type each search and what businesses pay Google for one ad click."
  end

  test "a run working on Step 4 says it filters and groups the phrases" do
    run = build(:run, status: :running, steps: build_run_steps(done_through(3, %{4 => :running})))

    assert StatusLine.sentence(%{run: run, progress: nil}) ==
             "I'm leaving out searches that aren't about the business and sorting the rest into topics."
  end

  test "a run working on Step 5 says it checks who answers the best phrases and when the choice comes" do
    run = build(:run, status: :running, steps: build_run_steps(done_through(4, %{5 => :running})))

    assert StatusLine.sentence(%{run: run, progress: nil}) ==
             "I'm checking who is on Google's first page for the searches people type most. After step 7 you choose a topic."
  end

  test "a run working on Step 5 with progress says how many phrases it has checked" do
    run = build(:run, status: :running, steps: build_run_steps(done_through(4, %{5 => :running})))
    progress = %{step: 5, checked: 7, total: 30, phrase: "fraza", holders: "guides and blogs", verdict: :weak}

    assert StatusLine.sentence(%{run: run, progress: progress}) ==
             "I'm checking who is on Google's first page for the searches people type most (7 of 30). After step 7 you choose a topic."
  end

  test "progress of another Step doesn't change the sentence" do
    run = build(:run, status: :running, steps: build_run_steps(done_through(5, %{6 => :running})))
    progress = %{step: 5, checked: 30, total: 30, phrase: "fraza", holders: "guides and blogs", verdict: :weak}

    assert StatusLine.sentence(%{run: run, progress: progress}) ==
             "I'm checking which searches the site already shows up for on Google."
  end

  test "a run working on Step 6 says it checks where the site is already visible" do
    run = build(:run, status: :running, steps: build_run_steps(done_through(5, %{6 => :running})))

    assert StatusLine.sentence(%{run: run, progress: nil}) ==
             "I'm checking which searches the site already shows up for on Google."
  end

  test "a run working on Step 7 says it scores the niches" do
    run = build(:run, status: :running, steps: build_run_steps(done_through(6, %{7 => :running})))

    assert StatusLine.sentence(%{run: run, progress: nil}) ==
             "I'm rating the topics out of 10: how often people search, the ad click price and how easy Google's first page is."
  end

  test "a run working on Step 8 says it writes the brief" do
    run = build(:run, status: :running, steps: build_run_steps(done_through(7, %{8 => :running})))

    assert StatusLine.sentence(%{run: run, progress: nil}) == "I'm writing the brief for the chosen topic."
  end

  test "a run with Step 8 queued already talks about writing the brief" do
    run = build(:run, status: :running, steps: build_run_steps(done_through(7, %{8 => :queued})))

    assert StatusLine.sentence(%{run: run, progress: nil}) == "I'm writing the brief for the chosen topic."
  end

  test "a running run between Steps talks about the next Step to run" do
    run = build(:run, status: :running, steps: build_run_steps(done_through(2)))

    assert StatusLine.sentence(%{run: run, progress: nil}) ==
             "I'm checking how many times a month people type each search and what businesses pay Google for one ad click."
  end

  test "a run awaiting a choice asks for a niche" do
    run = build(:run, status: :awaiting_choice, steps: build_run_steps(done_through(7)))

    assert StatusLine.sentence(%{run: run, progress: nil}) ==
             "The topics are rated. Choose one and I'll write a brief for it: the plan and the text for one page."
  end

  test "a stopped run says on which Step it stopped and that it can be resumed" do
    run = build(:run, status: :stopped, steps: build_run_steps(done_through(3)))

    assert StatusLine.sentence(%{run: run, progress: nil}) ==
             "I stopped the research at step 4. You can resume it."
  end

  test "a failed run names the failed Step and its reason" do
    run =
      build(:run,
        status: :failed,
        steps: Enum.map(build_run_steps(%{1 => :done, 2 => :failed}), &put_error(&1, 2, "No DataForSEO credentials"))
      )

    assert StatusLine.sentence(%{run: run, progress: nil}) ==
             "Step 2 failed: No DataForSEO credentials."
  end

  test "a failure reason ending with a full stop doesn't get a second one" do
    run =
      build(:run,
        status: :failed,
        steps: Enum.map(build_run_steps(%{1 => :failed}), &put_error(&1, 1, "The model did not answer."))
      )

    assert StatusLine.sentence(%{run: run, progress: nil}) == "Step 1 failed: The model did not answer."
  end

  test "the current Step of a running run is the one at work" do
    run = build(:run, status: :running, steps: build_run_steps(done_through(4, %{5 => :running})))

    assert %{number: 5} = StatusLine.current_step(run)
  end

  test "the current Step of a stopped run is the first one not finished" do
    run = build(:run, status: :stopped, steps: build_run_steps(done_through(5, %{6 => :skipped})))

    assert %{number: 7} = StatusLine.current_step(run)
  end

  test "a running run with no Step at work or left to chain says it works on the research" do
    run = build(:run, status: :running, steps: build_run_steps(done_through(7)))

    assert StatusLine.sentence(%{run: run, progress: nil}) == "I'm working on the research."
  end

  test "a run stopped with no Step left to chain says it stopped and can be resumed" do
    run = build(:run, status: :stopped, steps: build_run_steps(done_through(7)))

    assert StatusLine.sentence(%{run: run, progress: nil}) == "I stopped the research. You can resume it."
  end

  test "a failed run without a failed Step says the research failed" do
    run = build(:run, status: :failed, steps: build_run_steps(done_through(7)))

    assert StatusLine.sentence(%{run: run, progress: nil}) == "The research failed."
  end

  test "a failed Step without a stored reason reads as an unknown error" do
    run = build(:run, status: :failed, steps: build_run_steps(%{1 => :failed}))

    assert StatusLine.sentence(%{run: run, progress: nil}) == "Step 1 failed: unknown error."
  end

  defp done_through(last_number, overrides \\ %{}) do
    1..last_number
    |> Map.new(&{&1, :done})
    |> Map.merge(overrides)
  end

  defp put_error(%{number: number} = step, number, error), do: %{step | error: error}
  defp put_error(step, _number, _error), do: step
end
