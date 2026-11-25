defmodule Dirmoon.PriceChecks.PriceCheck do
  @moduledoc """
  A Price Check: the on-demand reading of one Niche's Competitor Pages for
  the prices they publish. One per Niche, started by the User from the
  results screen; it is not a Step and does not change the run's status.

  `status` is `:checking` from the User's request until every Competitor
  Page has an outcome, then `:done`; `:failed` with an `error` when the
  check gave up (the User may start it again; pages already read keep
  their outcome). Deleted with its Niche or run.
  """
  use Ecto.Schema

  alias Dirmoon.Niches.Niche
  alias Dirmoon.PriceChecks.CompetitorPage
  alias Dirmoon.Research.Run

  @statuses [:checking, :done, :failed]

  schema "price_checks" do
    field :status, Ecto.Enum, values: @statuses, default: :checking
    field :error, :string

    belongs_to :run, Run
    belongs_to :niche, Niche, foreign_key: :cluster_id
    has_many :competitor_pages, CompetitorPage, preload_order: [asc: :google_position, asc: :id]

    timestamps(type: :utc_datetime)
  end
end
