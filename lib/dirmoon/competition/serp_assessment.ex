defmodule Dirmoon.Competition.SerpAssessment do
  @moduledoc """
  How one Research Run reads a Phrase's SERP Snapshot: the Page Type of each
  result (`labels`, maps with `"position"` and `"page_type"`) and the
  competition `verdict`. Per run, so per Account: labels depend on the
  business, so they never go into the shared snapshot. `reused_snapshot`
  says whether the run took a fresh snapshot another fetch had stored
  instead of buying one.
  """
  use Ecto.Schema

  alias Dirmoon.Competition.SerpSnapshot
  alias Dirmoon.Phrases.Phrase
  alias Dirmoon.Research.Run

  @direct_competitor :direct_competitor
  @page_types [@direct_competitor, :directory, :forum, :portal, :blog]
  @weak_page_types [:blog, :forum, :directory]
  @verdicts [:weak, :medium, :strong]
  @page_type_plurals %{
    direct_competitor: "konkurenci",
    directory: "katalogi",
    forum: "fora",
    portal: "portale",
    blog: "blogi"
  }

  schema "serp_assessments" do
    field :labels, {:array, :map}, default: []
    field :verdict, Ecto.Enum, values: @verdicts
    field :reused_snapshot, :boolean, default: false

    belongs_to :run, Run
    belongs_to :phrase, Phrase, foreign_key: :keyword_id
    belongs_to :serp_snapshot, SerpSnapshot

    timestamps(type: :utc_datetime)
  end

  def page_types, do: @page_types

  @doc "The Page Type of a business offering the same as the run's business."
  def direct_competitor, do: @direct_competitor

  @doc "The Page Types that make a top 10 easy to break into: blogs, forums and directories."
  def weak_page_types, do: @weak_page_types

  def verdicts, do: @verdicts

  @doc "The Polish plural of each Page Type, as screens name who holds a top 10 (`blog` → \"blogi\")."
  def page_type_plurals, do: @page_type_plurals
end
