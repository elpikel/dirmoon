defmodule Dirmoon.Niches.Niche do
  @moduledoc """
  A Niche: a group of one Research Run's Phrases that share a search intent,
  as Step 4 proposed it, with the model's name, intent and two-sentence
  reading. `position` is the order the model returned it in, used before
  Step 7 sets the `score`. `phrase_count` is filled by
  `Dirmoon.Niches.list_for_run/1`.
  """
  use Ecto.Schema

  alias Dirmoon.Phrases.RunPhrase
  alias Dirmoon.Research.Run

  @statuses [:proposed, :rejected, :chosen]
  @choosable_statuses [:proposed, :chosen]
  @max_name_length 255

  schema "clusters" do
    field :name, :string
    field :intent, :string
    field :reading, :string
    field :score, :decimal
    field :score_components, :map
    field :status, Ecto.Enum, values: @statuses, default: :proposed
    field :position, :integer
    field :phrase_count, :integer, virtual: true

    belongs_to :run, Run
    has_many :run_phrases, RunPhrase, foreign_key: :cluster_id

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @doc "Whether the Niche is still on offer: proposed, or already chosen, but not rejected."
  def choosable?(%__MODULE__{status: status}), do: status in @choosable_statuses

  def max_name_length, do: @max_name_length
end
