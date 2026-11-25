defmodule Dirmoon.Pages.StatusLineTest do
  use ExUnit.Case, async: true

  import Dirmoon.Factory

  alias Dirmoon.Pages.Brief
  alias Dirmoon.Pages.StatusLine

  @approval "Odpowiedzi prawne, medyczne i finansowe musi zatwierdzić właściciel firmy przed publikacją."

  test "a ready page counts the Brief's questions and leaves prices and contact data to the User" do
    page = ready_page(%{mode: :new_idea, questions: 4})

    assert StatusLine.sentence(page) ==
             "Ułożyłem stronę z 4 pytań klientów. Ceny i dane kontaktowe uzupełniasz Ty."
  end

  test "the question count agrees with its noun" do
    assert StatusLine.sentence(ready_page(%{mode: :new_idea, questions: 1})) =~ "z 1 pytania klientów"
    assert StatusLine.sentence(ready_page(%{mode: :new_idea, questions: 3})) =~ "z 3 pytań klientów"
  end

  test "an Existing Site page adds that legal, medical or financial answers need the owner's approval" do
    page = ready_page(%{mode: :existing_site, questions: 2})

    assert StatusLine.sentence(page) ==
             "Ułożyłem stronę z 2 pytań klientów. Ceny i dane kontaktowe uzupełniasz Ty. " <> @approval
  end

  test "a page being written says so" do
    assert StatusLine.sentence(build(:page, status: :writing, brief: nil)) ==
             "Piszę brief i treść strony. Pokażę je tutaj, gdy skończę."
  end

  test "a page waiting on a stopped run says the research must be resumed" do
    stopped_run = build(:run, status: :stopped)

    assert StatusLine.sentence(build(:page, status: :writing, brief: nil, run: stopped_run)) ==
             "Research jest zatrzymany, więc brief czeka. Wznów go na ekranie researchu."
  end

  test "a failed page gives its error" do
    assert StatusLine.sentence(build(:page, status: :failed, brief: nil, error: "Model zwrócił niepoprawny brief")) ==
             "Brief się nie udał: Model zwrócił niepoprawny brief."

    assert StatusLine.sentence(build(:page, status: :failed, brief: nil, error: nil)) == "Brief się nie udał."
  end

  test "the pages list counts the pages, or invites the User to pick a Niche" do
    assert StatusLine.list_sentence([]) ==
             "Nie mam jeszcze żadnej strony. Wybierz niszę w wynikach, a napiszę dla niej brief."

    assert StatusLine.list_sentence(build_list(1, :page)) == "Mam 1 stronę dla Twoich nisz."
    assert StatusLine.list_sentence(build_list(3, :page)) == "Mam 3 strony dla Twoich nisz."
    assert StatusLine.list_sentence(build_list(5, :page)) == "Mam 5 stron dla Twoich nisz."
  end

  defp ready_page(%{mode: mode, questions: count}) do
    sections = Enum.map(1..count, &%Brief.Section{question: "Pytanie #{&1}?"})
    build(:page, status: :ready, run: build(:run, mode: mode), brief: build(:brief, sections: sections))
  end
end
