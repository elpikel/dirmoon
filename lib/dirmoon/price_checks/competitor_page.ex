defmodule Dirmoon.PriceChecks.CompetitorPage do
  @moduledoc """
  A Competitor Page: the address of one direct competitor's domain that a
  Price Check reads, the best-placed one on Google's first page for the
  Niche's Phrases (`google_position`). `read_url` is the address actually
  read after redirects.

  `outcome` is `:waiting` until the page is read, then `:prices_found`
  (with its verified Competitor Offers), `:no_prices` (the page was read
  but states no price the check could verify) or `:unreadable` (the page
  could not be opened).

  `facts` are the page's Page Facts that compare it with the site's own
  page (`Dirmoon.WebPage.PageFacts.comparison/1`), stored when the page is
  read; nil for a page that could not be opened, one that is not HTML, or
  one read before they were kept. `linking_sites` is how many other sites
  link to the page's domain, as DataForSEO's link index knows; nil when
  unknown (not asked, no data, or the request failed).
  """
  use Ecto.Schema

  alias Dirmoon.PriceChecks.CompetitorOffer
  alias Dirmoon.PriceChecks.PriceCheck

  @outcomes [:waiting, :prices_found, :no_prices, :unreadable]

  schema "competitor_pages" do
    field :google_position, :integer
    field :domain, :string
    field :url, :string
    field :read_url, :string
    field :outcome, Ecto.Enum, values: @outcomes, default: :waiting
    field :facts, :map
    field :linking_sites, :integer

    embeds_many :offers, CompetitorOffer, on_replace: :delete

    belongs_to :price_check, PriceCheck

    timestamps(type: :utc_datetime)
  end
end
