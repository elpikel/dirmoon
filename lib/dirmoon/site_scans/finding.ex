defmodule Dirmoon.SiteScans.Finding do
  @moduledoc """
  One thing a Site Scan tells the owner, worked out from the stored facts
  (`Dirmoon.SiteScans.Findings.build/1`). Never stored and never written by
  the LLM; the web layer turns it into sentences, keyed by `check`.

    * `question`: which of the plain questions it answers, one of
      `questions/0`, in display order
    * `check`: the check that made it (an atom, one per kind of Finding)
    * `level`: one of `levels/0`, in display order
    * `pages`: the addresses of the pages concerned, at most `max_pages/0`;
      `page_count` is how many there are in all
    * `figures`: the numbers and names behind it (atom keys, plain values)
  """

  @questions [:findable, :page_content, :niche_coverage, :visitor, :business]
  @levels [:problem, :warning, :not_checked, :good]
  @max_pages 20

  @enforce_keys [:question, :check, :level]
  defstruct [:question, :check, :level, pages: [], page_count: 0, figures: %{}]

  @doc "The questions Findings answer, in display order."
  def questions, do: @questions

  @doc "The levels of a Finding, in display order: problems first, good news last."
  def levels, do: @levels

  @doc "The most page addresses one Finding lists."
  def max_pages, do: @max_pages

  @doc """
  A Finding from `%{question:, check:, level:}` with optional `pages:`
  (addresses, repeated ones listed once) and `figures:`.
  """
  def new(%{question: question, check: check, level: level} = attributes)
      when question in @questions and is_atom(check) and level in @levels do
    pages = attributes |> Map.get(:pages, []) |> Enum.uniq()

    %__MODULE__{
      question: question,
      check: check,
      level: level,
      pages: Enum.take(pages, @max_pages),
      page_count: length(pages),
      figures: Map.get(attributes, :figures, %{})
    }
  end
end
