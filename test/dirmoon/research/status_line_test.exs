defmodule Dirmoon.Research.StatusLineTest do
  use ExUnit.Case, async: true

  import Dirmoon.Factory

  alias Dirmoon.Research.StatusLine

  test "a run working on Step 1 says it turns the description into seed phrases and questions" do
    run = build(:run, status: :running, steps: build_run_steps(%{1 => :running}))

    assert StatusLine.sentence(%{run: run, progress: nil}) == "Zamieniam opis na frazy startowe i pytania klientów."
  end

  test "a run working on Step 2 says it expands the seeds into what people type" do
    run = build(:run, status: :running, steps: build_run_steps(%{1 => :done, 2 => :running}))

    assert StatusLine.sentence(%{run: run, progress: nil}) ==
             "Rozwijam frazy startowe w to, co ludzie naprawdę wpisują."
  end

  test "a run working on Step 3 says it checks volumes and CPC" do
    run = build(:run, status: :running, steps: build_run_steps(done_through(2, %{3 => :running})))

    assert StatusLine.sentence(%{run: run, progress: nil}) == "Sprawdzam wolumeny i CPC dla każdej frazy."
  end

  test "a run working on Step 4 says it filters and groups the phrases" do
    run = build(:run, status: :running, steps: build_run_steps(done_through(3, %{4 => :running})))

    assert StatusLine.sentence(%{run: run, progress: nil}) ==
             "Odsiewam frazy spoza oferty i grupuję resztę w nisze."
  end

  test "a run working on Step 5 says it checks who answers the best phrases and when the choice comes" do
    run = build(:run, status: :running, steps: build_run_steps(done_through(4, %{5 => :running})))

    assert StatusLine.sentence(%{run: run, progress: nil}) ==
             "Sprawdzam, kto odpowiada na najlepsze frazy. Po kroku 7 wybierasz niszę."
  end

  test "a run working on Step 5 with progress says how many phrases it has checked" do
    run = build(:run, status: :running, steps: build_run_steps(done_through(4, %{5 => :running})))
    progress = %{step: 5, checked: 7, total: 30, phrase: "fraza", holders: "blogi", verdict: :weak}

    assert StatusLine.sentence(%{run: run, progress: progress}) ==
             "Sprawdzam, kto odpowiada na najlepsze frazy (7 z 30). Po kroku 7 wybierasz niszę."
  end

  test "progress of another Step doesn't change the sentence" do
    run = build(:run, status: :running, steps: build_run_steps(done_through(5, %{6 => :running})))
    progress = %{step: 5, checked: 30, total: 30, phrase: "fraza", holders: "blogi", verdict: :weak}

    assert StatusLine.sentence(%{run: run, progress: progress}) ==
             "Sprawdzam, na które frazy strona już jest widoczna."
  end

  test "a run working on Step 6 says it checks where the site is already visible" do
    run = build(:run, status: :running, steps: build_run_steps(done_through(5, %{6 => :running})))

    assert StatusLine.sentence(%{run: run, progress: nil}) ==
             "Sprawdzam, na które frazy strona już jest widoczna."
  end

  test "a run working on Step 7 says it scores the niches" do
    run = build(:run, status: :running, steps: build_run_steps(done_through(6, %{7 => :running})))

    assert StatusLine.sentence(%{run: run, progress: nil}) ==
             "Oceniam nisze po wolumenie, CPC i słabości konkurencji."
  end

  test "a run working on Step 8 says it writes the brief and content" do
    run = build(:run, status: :running, steps: build_run_steps(done_through(7, %{8 => :running})))

    assert StatusLine.sentence(%{run: run, progress: nil}) == "Piszę brief i treść dla wybranej niszy."
  end

  test "a run with Step 8 queued already talks about writing the brief" do
    run = build(:run, status: :running, steps: build_run_steps(done_through(7, %{8 => :queued})))

    assert StatusLine.sentence(%{run: run, progress: nil}) == "Piszę brief i treść dla wybranej niszy."
  end

  test "a run working on Step 9 says it publishes the page" do
    run = build(:run, status: :running, steps: build_run_steps(done_through(8, %{9 => :running})))

    assert StatusLine.sentence(%{run: run, progress: nil}) == "Publikuję stronę."
  end

  test "a running run between Steps talks about the next Step to run" do
    run = build(:run, status: :running, steps: build_run_steps(done_through(2)))

    assert StatusLine.sentence(%{run: run, progress: nil}) == "Sprawdzam wolumeny i CPC dla każdej frazy."
  end

  test "a run awaiting a choice asks for a niche" do
    run = build(:run, status: :awaiting_choice, steps: build_run_steps(done_through(7)))

    assert StatusLine.sentence(%{run: run, progress: nil}) ==
             "Nisze ocenione. Wybierz jedną, a napiszę dla niej stronę."
  end

  test "a stopped run says on which Step it stopped and that it can be resumed" do
    run = build(:run, status: :stopped, steps: build_run_steps(done_through(3)))

    assert StatusLine.sentence(%{run: run, progress: nil}) ==
             "Zatrzymałem research na kroku 4. Możesz go wznowić."
  end

  test "a failed run names the failed Step and its reason" do
    run =
      build(:run,
        status: :failed,
        steps:
          Enum.map(build_run_steps(%{1 => :done, 2 => :failed}), &put_error(&1, 2, "Brak danych logowania DataForSEO"))
      )

    assert StatusLine.sentence(%{run: run, progress: nil}) ==
             "Krok 2 się nie udał: Brak danych logowania DataForSEO."
  end

  test "a failure reason ending with a full stop doesn't get a second one" do
    run =
      build(:run,
        status: :failed,
        steps: Enum.map(build_run_steps(%{1 => :failed}), &put_error(&1, 1, "Model nie odpowiedział."))
      )

    assert StatusLine.sentence(%{run: run, progress: nil}) == "Krok 1 się nie udał: Model nie odpowiedział."
  end

  test "a done run says the page is published" do
    run = build(:run, status: :done, steps: build_run_steps(done_through(9)))

    assert StatusLine.sentence(%{run: run, progress: nil}) == "Strona opublikowana."
  end

  test "the current Step of a running run is the one at work" do
    run = build(:run, status: :running, steps: build_run_steps(done_through(4, %{5 => :running})))

    assert %{number: 5} = StatusLine.current_step(run)
  end

  test "the current Step of a stopped run is the first one not finished" do
    run = build(:run, status: :stopped, steps: build_run_steps(done_through(5, %{6 => :skipped})))

    assert %{number: 7} = StatusLine.current_step(run)
  end

  defp done_through(last_number, overrides \\ %{}) do
    1..last_number
    |> Map.new(&{&1, :done})
    |> Map.merge(overrides)
  end

  defp put_error(%{number: number} = step, number, error), do: %{step | error: error}
  defp put_error(step, _number, _error), do: step
end
