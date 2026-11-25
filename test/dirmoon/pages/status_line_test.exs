defmodule Dirmoon.Pages.StatusLineTest do
  use ExUnit.Case, async: true

  import Dirmoon.Factory

  alias Dirmoon.Pages.Brief
  alias Dirmoon.Pages.StatusLine

  @approval "The business owner must approve legal, medical and financial answers before publishing."

  test "a ready page counts the Brief's questions and leaves prices and contact data to the User" do
    page = ready_page(%{mode: :new_idea, questions: 4})

    assert StatusLine.sentence(page) ==
             "I wrote the brief: it answers 4 customer questions. You fill in the prices and contact details."
  end

  test "the question count agrees with its noun" do
    assert StatusLine.sentence(ready_page(%{mode: :new_idea, questions: 1})) =~ "it answers 1 customer question."
    assert StatusLine.sentence(ready_page(%{mode: :new_idea, questions: 3})) =~ "it answers 3 customer questions."
  end

  test "an Existing Site page adds that legal, medical or financial answers need the owner's approval" do
    page = ready_page(%{mode: :existing_site, questions: 2})

    assert StatusLine.sentence(page) ==
             "I wrote the brief: it answers 2 customer questions. You fill in the prices and contact details. " <>
               @approval
  end

  test "a page being written says so" do
    assert StatusLine.sentence(build(:page, status: :writing, brief: nil)) ==
             "I'm writing the brief. I'll show it here when I'm done."
  end

  test "a page waiting on a stopped run says the research must be resumed" do
    stopped_run = build(:run, status: :stopped)

    assert StatusLine.sentence(build(:page, status: :writing, brief: nil, run: stopped_run)) ==
             "The research is stopped, so the brief is waiting. Resume it on the research screen."
  end

  test "a failed page gives its error" do
    assert StatusLine.sentence(build(:page, status: :failed, brief: nil, error: "The model returned an invalid brief")) ==
             "The brief failed: The model returned an invalid brief."

    assert StatusLine.sentence(build(:page, status: :failed, brief: nil, error: nil)) == "The brief failed."
  end

  test "the briefs list counts the briefs, or invites the User to pick a Niche" do
    assert StatusLine.list_sentence([]) ==
             "No briefs yet. Choose a niche in the results and I'll write a brief for it."

    assert StatusLine.list_sentence(build_list(1, :page)) == "I have 1 brief for your niches."
    assert StatusLine.list_sentence(build_list(3, :page)) == "I have 3 briefs for your niches."
  end

  defp ready_page(%{mode: mode, questions: count}) do
    sections = Enum.map(1..count, &%Brief.Section{question: "Pytanie #{&1}?"})
    build(:page, status: :ready, run: build(:run, mode: mode), brief: build(:brief, sections: sections))
  end
end
