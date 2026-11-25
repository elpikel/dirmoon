defmodule Dirmoon.Pages.StatusLine do
  @moduledoc """
  The status sentences of Pages: one first-person line saying
  what dirmoon did or is doing with a page's Brief (the brief screen), and
  one about the Account's briefs (the "Briefs" list). Built only from stored state, never by
  the LLM; see `docs/design/README.md` sections 8.2 and 8.4.

  An Existing Site page's sentence adds that legal, medical and financial
  answers must be approved by the business owner before publishing.
  """

  alias Dirmoon.Format
  alias Dirmoon.Pages.Brief
  alias Dirmoon.Pages.Page
  alias Dirmoon.Research.Run

  @question_forms %{one: "customer question", other: "customer questions"}
  @brief_forms %{one: "brief", other: "briefs"}

  @sentences %{
    writing: "I'm writing the brief. I'll show it here when I'm done.",
    writing_on_stopped_run: "The research is stopped, so the brief is waiting. Resume it on the research screen.",
    failed: "The brief failed: %{reason}.",
    failed_without_reason: "The brief failed.",
    ready: "I wrote the brief: it answers %{count} %{questions}. You fill in the prices and contact details.",
    approval: "The business owner must approve legal, medical and financial answers before publishing.",
    no_briefs: "No briefs yet. Choose a niche in the results and I'll write a brief for it.",
    briefs: "I have %{count} %{briefs} for your niches."
  }

  @doc """
  The status sentence of a page with its run preloaded (`Pages.get_page/2`).
  A page being written on a stopped run says it waits for the research to be
  resumed.
  """
  def sentence(%Page{status: :writing, run: %Run{status: :stopped}}), do: @sentences.writing_on_stopped_run
  def sentence(%Page{status: :writing}), do: @sentences.writing
  def sentence(%Page{status: :failed, error: nil}), do: @sentences.failed_without_reason

  def sentence(%Page{status: :failed, error: error}) do
    reason = String.trim_trailing(error, ".")
    String.replace(@sentences.failed, "%{reason}", reason)
  end

  def sentence(%Page{status: :ready, brief: %Brief{sections: sections}, run: %Run{mode: mode}}) do
    count = length(sections)
    count_text = Integer.to_string(count)
    questions = Format.plural(count, @question_forms)

    @sentences.ready
    |> String.replace("%{count}", count_text)
    |> String.replace("%{questions}", questions)
    |> with_approval(mode)
  end

  @doc """
  The status sentence of the Account's briefs list.
  """
  def list_sentence([]), do: @sentences.no_briefs

  def list_sentence(pages) when is_list(pages) do
    count = length(pages)
    count_text = Integer.to_string(count)
    noun = Format.plural(count, @brief_forms)

    @sentences.briefs
    |> String.replace("%{count}", count_text)
    |> String.replace("%{briefs}", noun)
  end

  defp with_approval(sentence, :existing_site), do: sentence <> " " <> @sentences.approval
  defp with_approval(sentence, :new_idea), do: sentence
end
