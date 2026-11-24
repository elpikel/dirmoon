defmodule Dirmoon.Pages.StatusLine do
  @moduledoc """
  The status sentences of Produced Pages: one first-person Polish line saying
  what dirmoon did or is doing with a page (screen 4), and one about the
  Account's pages (the "Strony" list). Built only from stored state, never by
  the LLM; see `docs/design/README.md` sections 8.2 and 8.4.

  An Existing Site page's sentence adds that legal, medical and financial
  answers must be approved by the business owner before publishing.
  """

  alias Dirmoon.Pages.Brief
  alias Dirmoon.Pages.Page
  alias Dirmoon.Polish
  alias Dirmoon.Research.Run

  @question_forms %{one: "pytania", few: "pytań", many: "pytań"}
  @page_forms %{one: "stronę", few: "strony", many: "stron"}

  @sentences %{
    writing: "Piszę brief i treść strony. Pokażę je tutaj, gdy skończę.",
    publishing: "Publikuję stronę na Netlify. Adres pojawi się tutaj, gdy skończę.",
    writing_on_stopped_run: "Research jest zatrzymany, więc brief czeka. Wznów go na ekranie researchu.",
    publishing_on_stopped_run: "Research jest zatrzymany, więc publikacja czeka. Wznów go na ekranie researchu.",
    failed: "Brief się nie udał: %{reason}.",
    failed_without_reason: "Brief się nie udał.",
    ready: "Ułożyłem stronę z %{count} %{questions} klientów. Ceny i dane kontaktowe uzupełniasz Ty.",
    published: "Opublikowałem stronę z %{count} %{questions} klientów. Ceny i dane kontaktowe uzupełniasz Ty.",
    approval: "Odpowiedzi prawne, medyczne i finansowe musi zatwierdzić właściciel firmy przed publikacją.",
    no_pages: "Nie mam jeszcze żadnej strony. Wybierz niszę w wynikach, a napiszę dla niej brief.",
    pages: "Mam %{count} %{pages} dla Twoich nisz."
  }

  @doc """
  The status sentence of a page with its run preloaded (`Pages.get_page/2`).
  A page being written or published on a stopped run says it waits for the
  research to be resumed.
  """
  def sentence(%Page{status: :writing, run: %Run{status: :stopped}}), do: @sentences.writing_on_stopped_run
  def sentence(%Page{status: :publishing, run: %Run{status: :stopped}}), do: @sentences.publishing_on_stopped_run
  def sentence(%Page{status: :writing}), do: @sentences.writing
  def sentence(%Page{status: :publishing}), do: @sentences.publishing
  def sentence(%Page{status: :failed, error: nil}), do: @sentences.failed_without_reason

  def sentence(%Page{status: :failed, error: error}) do
    reason = String.trim_trailing(error, ".")
    String.replace(@sentences.failed, "%{reason}", reason)
  end

  def sentence(%Page{status: status, brief: %Brief{sections: sections}, run: %Run{mode: mode}})
      when status in [:ready, :published] do
    count = length(sections)
    count_text = Integer.to_string(count)
    questions = Polish.plural(count, @question_forms)
    template = Map.fetch!(@sentences, status)

    template
    |> String.replace("%{count}", count_text)
    |> String.replace("%{questions}", questions)
    |> with_approval(mode)
  end

  @doc """
  The status sentence of the Account's pages list.
  """
  def list_sentence([]), do: @sentences.no_pages

  def list_sentence(pages) when is_list(pages) do
    count = length(pages)
    count_text = Integer.to_string(count)
    noun = Polish.plural(count, @page_forms)

    @sentences.pages
    |> String.replace("%{count}", count_text)
    |> String.replace("%{pages}", noun)
  end

  defp with_approval(sentence, :existing_site), do: sentence <> " " <> @sentences.approval
  defp with_approval(sentence, :new_idea), do: sentence
end
