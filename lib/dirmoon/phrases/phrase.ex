defmodule Dirmoon.Phrases.Phrase do
  @moduledoc """
  A Phrase: a search query people really type, as the keyword API returned
  it, in one language. Shared market data (ADR-0002): it holds nothing that
  identifies an Account, a run or a business.
  """
  use Ecto.Schema

  alias Dirmoon.Phrases.Metrics

  schema "keywords" do
    field :phrase, :string
    field :language_code, :string

    has_many :metrics, Metrics, foreign_key: :keyword_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  The stored form of a Phrase: trimmed, lowercased, inner whitespace
  collapsed to single spaces.

      iex> Dirmoon.Phrases.Phrase.normalise("  Hotel   dla PSÓW ")
      "hotel dla psów"
  """
  def normalise(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.split()
    |> Enum.join(" ")
  end
end
