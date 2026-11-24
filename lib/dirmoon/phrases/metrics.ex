defmodule Dirmoon.Phrases.Metrics do
  @moduledoc """
  A Phrase's Metrics in one location (`location_code`), as last fetched: its
  Volume (`search_volume`), CPC (`cpc` in `currency`) and Trend (`trend`,
  stored in the provider-named `monthly_searches` column, newest month first,
  as maps with `"year"`, `"month"` and `"search_volume"`). Shared market data
  (ADR-0002): one row per Phrase and location, replaced only by a fetch newer
  than the stored one (`fetched_at`).
  """
  use Ecto.Schema

  alias Dirmoon.Phrases.Phrase

  schema "keyword_metrics" do
    field :location_code, :integer
    field :search_volume, :integer
    field :cpc, :decimal
    field :currency, :string
    field :trend, {:array, :map}, default: [], source: :monthly_searches
    field :fetched_at, :utc_datetime
    field :raw, :map

    belongs_to :phrase, Phrase, foreign_key: :keyword_id

    timestamps(type: :utc_datetime)
  end
end
