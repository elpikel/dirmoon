defmodule Dirmoon.SiteScans.ScannedPage do
  @moduledoc """
  A Scanned Page: one page of the site a Site Scan read, in read order
  (`position`): its address, the HTTP status it answered with (nil when it
  gave none), its Page Facts and the Niche it was matched to, if any. Unique
  per scan and address; deleted with its scan, and loses its Niche when the
  Niche is deleted.

  A readable page (`readable?/1`) is one of the site's own HTML pages that
  answered HTTP 200 with its Page Facts (they always hold `"word_count"`),
  never a page whose read ended on another host (`"off_site"`).
  """
  use Ecto.Schema

  alias Dirmoon.Niches.Niche
  alias Dirmoon.SiteScans.SiteScan

  @readable_status 200

  schema "scanned_pages" do
    field :url, :string
    field :http_status, :integer
    field :facts, :map, default: %{}
    field :position, :integer

    belongs_to :site_scan, SiteScan
    belongs_to :niche, Niche, foreign_key: :cluster_id

    timestamps(type: :utc_datetime)
  end

  @doc "Whether the page is one of the site's own HTML pages, read with its Page Facts."
  def readable?(%{http_status: @readable_status, facts: %{"word_count" => _word_count} = facts}),
    do: facts["off_site"] != true

  def readable?(_page), do: false
end
