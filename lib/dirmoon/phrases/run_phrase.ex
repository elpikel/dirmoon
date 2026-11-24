defmodule Dirmoon.Phrases.RunPhrase do
  @moduledoc """
  A Phrase as one Research Run sees it: where it came from (`origin`),
  whether the run kept or rejected it and why, the Niche Step 4 put it in
  (`cluster_id`), and the site's Current Position. Per run, so per Account. `volume` is filled by
  `Dirmoon.Phrases.list_for_run/1` with the Volume for the run's country,
  `city_volume` with the Volume for the run's city location.
  """
  use Ecto.Schema

  alias Dirmoon.Niches.Niche
  alias Dirmoon.Phrases.Phrase
  alias Dirmoon.Research.Run

  @origins [:seed, :expansion]
  @statuses [:kept, :rejected]

  schema "run_keywords" do
    field :origin, Ecto.Enum, values: @origins
    field :status, Ecto.Enum, values: @statuses, default: :kept
    field :rejection_reason, :string
    field :current_position, :decimal
    field :volume, :any, virtual: true
    field :city_volume, :any, virtual: true

    belongs_to :run, Run
    belongs_to :phrase, Phrase, foreign_key: :keyword_id
    belongs_to :niche, Niche, foreign_key: :cluster_id

    timestamps(type: :utc_datetime)
  end

  def origins, do: @origins

  def statuses, do: @statuses
end
