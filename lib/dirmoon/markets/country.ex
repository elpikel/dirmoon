defmodule Dirmoon.Markets.Country do
  @moduledoc """
  A country a Research Run can target, as the keyword API lists it (a Google
  Ads location of type Country): its ISO code (`country_code`), the keyword
  API's `location_code` and its English `name`. Cached in `market_countries`,
  all rows of one list sharing the `fetched_at` of the fetch that stored them.
  """
  use Ecto.Schema

  @primary_key false
  schema "market_countries" do
    field :country_code, :string
    field :location_code, :integer
    field :name, :string
    field :fetched_at, :utc_datetime
  end
end
