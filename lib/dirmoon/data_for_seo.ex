defmodule Dirmoon.DataForSEO do
  @moduledoc """
  The seam to DataForSEO: phrase ideas, search volumes, the Google top 10,
  the Phrases a domain ranks for, Google's rough count of a domain's
  indexed pages, a business's Google Business Profile, how many other sites
  link to a domain, city location lookup, and the countries and languages the
  keyword endpoints accept (both lists are free). The adapter is chosen by
  `config :dirmoon, :data_for_seo_adapter`.

  Every paid call answers with parsed `rows` (atom keys), the `raw` response
  body and the `cost` DataForSEO reports. CPC is in USD.
  """

  @max_seeds 20
  @max_phrases 1000
  @max_linking_sites_domains 20

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
  @type ranked_phrase_row :: %{
          phrase: String.t(),
          position: integer(),
          url: String.t(),
          search_volume: integer() | nil
        }
  @type location_request :: %{city: String.t(), country_code: String.t()}
  @type ranked_phrases_unavailable :: %{message: String.t(), raw: map(), cost: Decimal.t()}
  @type ranked_phrases_request :: %{
          domain: String.t(),
          location_code: integer(),
          language_code: String.t(),
          limit: pos_integer()
        }
  @type indexed_page_count_request :: %{domain: String.t(), location_code: integer(), language_code: String.t()}
  @type indexed_page_count :: {:ok, %{count: non_neg_integer(), raw: map(), cost: Decimal.t()}} | {:error, term()}
  @type business_profile_request :: %{name: String.t(), location_code: integer(), language_code: String.t()}
  @type business_profile :: %{
          title: String.t() | nil,
          address: String.t() | nil,
          phone: String.t() | nil,
          url: String.t() | nil,
          domain: String.t() | nil,
          rating: number() | nil,
          votes: integer() | nil,
          claimed: boolean() | nil
        }
  @type business_profile_unavailable :: %{message: String.t(), raw: map(), cost: Decimal.t()}
  @type business_profile_answer ::
          {:ok, %{profile: business_profile() | nil, raw: map(), cost: Decimal.t()}}
          | {:error, {:business_profile_unavailable, business_profile_unavailable()} | term()}
  @type linking_sites_request :: %{domains: [String.t()]}
  @type linking_sites_row :: %{domain: String.t(), linking_sites: non_neg_integer()}
  @type linking_sites_unavailable :: %{message: String.t(), raw: map(), cost: Decimal.t()}
  @type country :: %{country_code: String.t(), location_code: integer(), name: String.t()}
  @type language :: %{language_code: String.t(), name: String.t()}

  @callback phrase_ideas(phrase_ideas_request()) :: answer(phrase_row())
  @callback search_volumes(search_volumes_request()) :: answer(phrase_row())
  @callback serp_top10(serp_request()) :: answer(serp_row())
  @callback ranked_phrases(ranked_phrases_request()) ::
              answer(ranked_phrase_row()) | {:error, {:ranked_phrases_unavailable, ranked_phrases_unavailable()}}
  @callback indexed_page_count(indexed_page_count_request()) :: indexed_page_count()
  @callback business_profile(business_profile_request()) :: business_profile_answer()
  @callback linking_sites(linking_sites_request()) ::
              answer(linking_sites_row()) | {:error, {:linking_sites_unavailable, linking_sites_unavailable()}}
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

  @doc """
  The Phrases `domain` (a bare host, without `www.`) ranks for on Google in
  organic results, up to `limit` of them (DataForSEO allows 1,000): each
  with its organic position, the address that ranks and its monthly Volume
  (nil when unknown), from DataForSEO Labs' own weekly index, so a small or
  new site may have none.

  Labs targets countries only: pass the run's **country** location code,
  never a city's. When DataForSEO answers but fails the task itself (a
  country or language Labs does not cover, among other reasons), the answer
  is `{:error, {:ranked_phrases_unavailable, %{message:, raw:, cost:}}}`
  with the cost DataForSEO reports, so the caller records it and carries on
  with other sources. Demo Data has none: `{:error, :not_in_demo_data}`.
  Any other failure (no answer, a server error, the account's access or
  funds refused) is `{:error, reason}`, to retry.
  """
  @spec ranked_phrases(ranked_phrases_request()) ::
          answer(ranked_phrase_row()) | {:error, {:ranked_phrases_unavailable, ranked_phrases_unavailable()}}
  def ranked_phrases(request), do: adapter().ranked_phrases(request)

  @doc """
  Google's rough count of the pages it holds for `domain` (the result count
  of a `site:` search in the location, a city or a country), with the raw
  response and cost. A search with no results, or no count in the answer,
  is `count: 0`, not an error. It is Google's estimate: show it as
  approximate.
  """
  @spec indexed_page_count(indexed_page_count_request()) :: indexed_page_count()
  def indexed_page_count(request), do: adapter().indexed_page_count(request)

  @doc """
  The Google Business Profile Google shows for a business `name` in a
  location (a city or a country), from DataForSEO's Business Data: its
  name as Google shows it (`title`), address, phone, the website it links
  to (`url`) and that site's host (`domain`, as Google gives it, `www.`
  kept), its rating with the number of votes, and whether the owner
  claimed it. `profile: nil` when Google has none for the name.

  When DataForSEO answers but fails the task itself (a location or
  language Business Data does not cover, among other reasons), the answer
  is `{:error, {:business_profile_unavailable, %{message:, raw:, cost:}}}`
  with the cost DataForSEO reports, so the caller records it and carries
  on. Demo Data has none: `{:error, :not_in_demo_data}`. Any other failure
  (no answer, a server error, the account's access or funds refused) is
  `{:error, reason}`.
  """
  @spec business_profile(business_profile_request()) :: business_profile_answer()
  def business_profile(request), do: adapter().business_profile(request)

  @doc """
  How many other sites link to each of up to #{@max_linking_sites_domains} `domains` (bare
  hosts), in one request: the distinct sites (root domains) DataForSEO's
  own link index knows to link to the domain, its subdomains included. It
  is a third-party index, not the whole web: show the number as
  approximate. Each domain is sent lower-cased without `www.`, an
  international name in its ASCII form (`Dirmoon.WebPage.HostName`), once; a
  row's `domain` is the domain as sent. A domain the answer says nothing
  about has no row (no data, never zero). More than
  #{@max_linking_sites_domains} domains is `{:error, :too_many_domains}`; none is an
  empty answer, at no cost and without a request.

  When DataForSEO answers but refuses the task itself (no access to its
  link data among other reasons), the answer is
  `{:error, {:linking_sites_unavailable, %{message:, raw:, cost:}}}` with
  the cost it reports, so the caller records it and carries on. Demo Data
  has none: `{:error, :not_in_demo_data}`. Any other failure is
  `{:error, reason}`.
  """
  @spec linking_sites(linking_sites_request()) ::
          answer(linking_sites_row()) | {:error, {:linking_sites_unavailable, linking_sites_unavailable()}}
  def linking_sites(request), do: adapter().linking_sites(request)

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

  @doc "How many domains one linking sites request may carry."
  def max_linking_sites_domains, do: @max_linking_sites_domains

  @doc "`:ok` when `phrases` fit in one request of at most `limit`, else `{:error, :too_many_phrases}`."
  @spec ensure_within_limit([String.t()], pos_integer()) :: :ok | {:error, :too_many_phrases}
  def ensure_within_limit(phrases, limit) when length(phrases) <= limit, do: :ok
  def ensure_within_limit(_phrases, _limit), do: {:error, :too_many_phrases}

  defp adapter, do: Application.fetch_env!(:dirmoon, :data_for_seo_adapter)
end
