defmodule Dirmoon.DataForSEO do
  @moduledoc """
  The seam to DataForSEO: keyword ideas, search volumes, the Google top 10
  and city location lookup. The adapter is chosen by
  `config :dirmoon, :data_for_seo_adapter`.

  Every paid call answers with parsed `rows` (atom keys), the `raw` response
  body and the `cost` DataForSEO reports. CPC is in USD.
  """

  @max_seeds 20
  @max_phrases 1000

  @type monthly_search :: %{year: integer(), month: integer(), search_volume: integer() | nil}
  @type keyword_row :: %{
          phrase: String.t(),
          search_volume: integer() | nil,
          cpc: Decimal.t() | nil,
          currency: String.t(),
          monthly_searches: [monthly_search()]
        }
  @type serp_row :: %{position: integer(), url: String.t(), domain: String.t(), title: String.t() | nil}
  @type answer(row) :: {:ok, %{rows: [row], raw: map(), cost: Decimal.t()}} | {:error, term()}
  @type location :: %{location_code: integer(), name: String.t(), raw: map(), cost: Decimal.t()}

  @type keyword_ideas_request :: %{seeds: [String.t()], location_code: integer(), language_code: String.t()}
  @type search_volumes_request :: %{phrases: [String.t()], location_code: integer(), language_code: String.t()}
  @type serp_request :: %{phrase: String.t(), location_code: integer(), language_code: String.t()}
  @type location_request :: %{city: String.t(), country_code: String.t()}

  @callback keyword_ideas(keyword_ideas_request()) :: answer(keyword_row())
  @callback search_volumes(search_volumes_request()) :: answer(keyword_row())
  @callback serp_top10(serp_request()) :: answer(serp_row())
  @callback find_location(location_request()) :: {:ok, location()} | {:error, :not_found | term()}

  @doc "Phrases related to up to #{@max_seeds} seeds, with country volumes."
  @spec keyword_ideas(keyword_ideas_request()) :: answer(keyword_row())
  def keyword_ideas(request), do: adapter().keyword_ideas(request)

  @doc "Volume, CPC and trend for up to #{@max_phrases} phrases."
  @spec search_volumes(search_volumes_request()) :: answer(keyword_row())
  def search_volumes(request), do: adapter().search_volumes(request)

  @doc "The organic Google top 10 for one phrase."
  @spec serp_top10(serp_request()) :: answer(serp_row())
  def serp_top10(request), do: adapter().serp_top10(request)

  @doc "The location code of a city in a country, or `{:error, :not_found}`."
  @spec find_location(location_request()) :: {:ok, location()} | {:error, :not_found | term()}
  def find_location(request), do: adapter().find_location(request)

  @doc "How many seeds one keyword ideas request may carry."
  def max_seeds, do: @max_seeds

  @doc "How many phrases one search volumes request may carry."
  def max_phrases, do: @max_phrases

  @doc "`:ok` when `keywords` fit in one request of at most `limit`, else `{:error, :too_many_keywords}`."
  @spec ensure_within_limit([String.t()], pos_integer()) :: :ok | {:error, :too_many_keywords}
  def ensure_within_limit(keywords, limit) when length(keywords) <= limit, do: :ok
  def ensure_within_limit(_keywords, _limit), do: {:error, :too_many_keywords}

  defp adapter, do: Application.fetch_env!(:dirmoon, :data_for_seo_adapter)
end
