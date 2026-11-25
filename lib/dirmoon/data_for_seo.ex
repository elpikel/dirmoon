defmodule Dirmoon.DataForSEO do
  @moduledoc """
  The seam to DataForSEO: phrase ideas, search volumes, the Google top 10,
  city location lookup, and the countries and languages the keyword
  endpoints accept (both lists are free). The adapter is chosen by
  `config :dirmoon, :data_for_seo_adapter`.

  Every paid call answers with parsed `rows` (atom keys), the `raw` response
  body and the `cost` DataForSEO reports. CPC is in USD.
  """

  @max_seeds 20
  @max_phrases 1000

  @type trend_month :: %{year: integer(), month: integer(), search_volume: integer() | nil}
  @type phrase_row :: %{
          phrase: String.t(),
          search_volume: integer() | nil,
          cpc: Decimal.t() | nil,
          currency: String.t(),
          trend: [trend_month()]
        }
  @type serp_row :: %{position: integer(), url: String.t(), domain: String.t(), title: String.t() | nil}
  @type answer(row) :: {:ok, %{rows: [row], raw: map(), cost: Decimal.t()}} | {:error, term()}
  @type location :: %{location_code: integer(), name: String.t(), raw: map(), cost: Decimal.t()}

  @type phrase_ideas_request :: %{seeds: [String.t()], location_code: integer(), language_code: String.t()}
  @type search_volumes_request :: %{phrases: [String.t()], location_code: integer(), language_code: String.t()}
  @type serp_request :: %{phrase: String.t(), location_code: integer(), language_code: String.t()}
  @type location_request :: %{city: String.t(), country_code: String.t()}
  @type country :: %{country_code: String.t(), location_code: integer(), name: String.t()}
  @type language :: %{language_code: String.t(), name: String.t()}

  @callback phrase_ideas(phrase_ideas_request()) :: answer(phrase_row())
  @callback search_volumes(search_volumes_request()) :: answer(phrase_row())
  @callback serp_top10(serp_request()) :: answer(serp_row())
  @callback find_location(location_request()) :: {:ok, location()} | {:error, :not_found | term()}
  @callback countries() :: {:ok, [country()]} | {:error, term()}
  @callback languages() :: {:ok, [language()]} | {:error, term()}

  @doc "Phrases related to up to #{@max_seeds} seeds, with country volumes."
  @spec phrase_ideas(phrase_ideas_request()) :: answer(phrase_row())
  def phrase_ideas(request), do: adapter().phrase_ideas(request)

  @doc "Volume, CPC and trend for up to #{@max_phrases} phrases."
  @spec search_volumes(search_volumes_request()) :: answer(phrase_row())
  def search_volumes(request), do: adapter().search_volumes(request)

  @doc "The organic Google top 10 for one phrase."
  @spec serp_top10(serp_request()) :: answer(serp_row())
  def serp_top10(request), do: adapter().serp_top10(request)

  @doc "The location code of a city in a country, or `{:error, :not_found}`."
  @spec find_location(location_request()) :: {:ok, location()} | {:error, :not_found | term()}
  def find_location(request), do: adapter().find_location(request)

  @doc "Every country the keyword endpoints target (Google Ads locations of type Country), at no cost."
  @spec countries() :: {:ok, [country()]} | {:error, term()}
  def countries, do: adapter().countries()

  @doc "Every language the keyword endpoints accept, at no cost."
  @spec languages() :: {:ok, [language()]} | {:error, term()}
  def languages, do: adapter().languages()

  @doc "How many seeds one phrase ideas request may carry."
  def max_seeds, do: @max_seeds

  @doc "How many phrases one search volumes request may carry."
  def max_phrases, do: @max_phrases

  @doc "`:ok` when `phrases` fit in one request of at most `limit`, else `{:error, :too_many_phrases}`."
  @spec ensure_within_limit([String.t()], pos_integer()) :: :ok | {:error, :too_many_phrases}
  def ensure_within_limit(phrases, limit) when length(phrases) <= limit, do: :ok
  def ensure_within_limit(_phrases, _limit), do: {:error, :too_many_phrases}

  defp adapter, do: Application.fetch_env!(:dirmoon, :data_for_seo_adapter)
end
