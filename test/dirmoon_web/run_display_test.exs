defmodule DirmoonWeb.RunDisplayTest do
  use Dirmoon.DataCase, async: true

  alias Dirmoon.Competition.SerpAssessment
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.RunStep
  alias DirmoonWeb.RunDisplay

  test "every run status has a label" do
    for status <- Run.statuses() do
      assert is_binary(RunDisplay.status_label(status))
    end
  end

  test "every Mode has a label" do
    for mode <- Run.modes() do
      assert is_binary(RunDisplay.mode_label(mode))
    end
  end

  test "every Step status has a label" do
    for status <- RunStep.statuses() do
      assert is_binary(RunDisplay.step_status_label(status))
    end
  end

  test "a Phrase whose competition was not checked reads muted" do
    assert RunDisplay.verdict_class(nil) == "text-on-app-muted"
  end

  test "every competition verdict has a label and a colour" do
    for verdict <- SerpAssessment.verdicts() do
      assert is_binary(RunDisplay.verdict_label(verdict))
      assert is_binary(RunDisplay.verdict_class(verdict))
    end
  end

  test "each competition verdict says how hard it is to get onto Google's first page" do
    assert Enum.map(SerpAssessment.verdicts(), &RunDisplay.verdict_meaning/1) == [
             "easy to get onto Google's first page",
             "possible to get onto Google's first page, but not at once",
             "hard to get onto Google's first page"
           ]
  end

  test "the market and location read the country and language names stored on the run" do
    run =
      build(:run,
        country_code: "BR",
        country_name: "Brazil",
        language_code: "pt",
        language_name: "Portuguese",
        city: "Recife"
      )

    assert RunDisplay.market(run) == "Brazil · Portuguese"
    assert RunDisplay.location(run) == "Brazil · Recife"
    assert RunDisplay.location(%{run | city: nil}) == "Brazil"
  end

  test "the short description is the description's first sentence" do
    assert RunDisplay.short_description("Hotel dla psów. Spacery i opieka.") == "Hotel dla psów"
    assert RunDisplay.short_description("Hotel dla psów!\nSpacery") == "Hotel dla psów"
  end

  test "a first sentence longer than 48 characters is cut at a word boundary with an ellipsis" do
    description = "Wypożyczalnia rowerów cargo z dostawą pod same drzwi klienta w całym mieście. Reszta."

    assert RunDisplay.short_description(description) == "Wypożyczalnia rowerów cargo z dostawą pod same…"
  end

  test "a run whose Step 7 has finished leads to its results" do
    run =
      insert(:run, status: :running, steps: 1..7 |> Map.new(&{&1, :done}) |> Map.put(8, :running) |> build_run_steps())

    assert RunDisplay.path(run) == "/app/runs/#{run.id}/results"
  end

  test "a run before Step 7 has finished leads to the run screen" do
    run = insert(:run, status: :failed, steps: build_run_steps(%{1 => :done, 2 => :failed}))

    assert RunDisplay.path(run) == "/app/runs/#{run.id}"
  end

  test "a page's path is the page screen" do
    page = insert(:page, run: insert(:run))

    assert RunDisplay.page_path(page) == "/app/pages/#{page.id}"
  end
end
