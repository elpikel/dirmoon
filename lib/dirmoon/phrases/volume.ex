defmodule Dirmoon.Phrases.Volume do
  @moduledoc """
  A Phrase's Volume, CPC and Trend in one location (`location_code`), as last
  fetched. Shared market data (ADR-0002): one row per Phrase and location,
  replaced only by a fetch newer than the stored one (`fetched_at`).
  `monthly_searches` is the Trend, newest first, as maps with `"year"`, `"month"` and `"search_volume"`.
  """
  use Ecto.Schema

  alias Dirmoon.Phrases.Phrase

  schema "keyword_metrics" do
    field :location_code, :integer
    field :search_volume, :integer
    field :cpc, :decimal
    field :currency, :string
    field :monthly_searches, {:array, :map}, default: []
    field :fetched_at, :utc_datetime
    field :raw, :map

    belongs_to :phrase, Phrase, foreign_key: :keyword_id

    timestamps(type: :utc_datetime)
  end
end
