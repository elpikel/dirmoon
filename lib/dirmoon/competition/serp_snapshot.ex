defmodule Dirmoon.Competition.SerpSnapshot do
  @moduledoc """
  A SERP Snapshot: Google's organic top 10 for a Phrase in one location, as
  fetched at `fetched_at`. Shared market data (ADR-0002): it never holds
  anything about a run, an Account or a business. Append-only: a new fetch
  adds a row, and the freshest one is reused while it is young enough.
  `results` are maps with `"position"`, `"url"`, `"domain"` and `"title"`,
  in position order; `raw` is the provider's response body.
  """
  use Ecto.Schema

  alias Dirmoon.Phrases.Phrase

  schema "serp_snapshots" do
    field :location_code, :integer
    field :language_code, :string
    field :fetched_at, :utc_datetime
    field :results, {:array, :map}, default: []
    field :raw, :map

    belongs_to :phrase, Phrase, foreign_key: :keyword_id

    timestamps(type: :utc_datetime)
  end
end
