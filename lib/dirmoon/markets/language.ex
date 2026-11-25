defmodule Dirmoon.Markets.Language do
  @moduledoc """
  A language the keyword API accepts for a Research Run's Phrases: its code
  (`language_code`, ISO 639-1 as the API gives it) and English `name`. Cached
  in `market_languages`, all rows of one list sharing the `fetched_at` of the
  fetch that stored them.
  """
  use Ecto.Schema

  @primary_key false
  schema "market_languages" do
    field :language_code, :string
    field :name, :string
    field :fetched_at, :utc_datetime
  end
end
