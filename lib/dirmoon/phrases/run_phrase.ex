defmodule Dirmoon.Phrases.RunPhrase do
  @moduledoc """
  A Phrase as one Research Run sees it: whether the run kept or rejected it
  and why, the Niche Step 4 put it in
  (`cluster_id`), and the site's Current Position with the address that ranks, when known. Per run, so per Account. `metrics` is filled by
  `Dirmoon.Phrases.list_for_run/1` with the Metrics for the run's country,
  `city_metrics` with the Metrics for the run's city location.
  """
  use Ecto.Schema

  alias Dirmoon.Niches.Niche
  alias Dirmoon.Phrases.Phrase
  alias Dirmoon.Research.Run

  @statuses [:kept, :rejected]

  schema "run_keywords" do
    field :status, Ecto.Enum, values: @statuses, default: :kept
    field :rejection_reason, :string
    field :current_position, :decimal
    field :current_position_url, :string
    field :metrics, :any, virtual: true
    field :city_metrics, :any, virtual: true

    belongs_to :run, Run
    belongs_to :phrase, Phrase, foreign_key: :keyword_id
    belongs_to :niche, Niche, foreign_key: :cluster_id

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
end
