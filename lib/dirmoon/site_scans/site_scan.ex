defmodule Dirmoon.SiteScans.SiteScan do
  @moduledoc """
  A Site Scan: the reading of an Existing Site's own pages, one per Research
  Run, started with the run. It is not a Step and never changes the run's
  status.

  `status` is `:scanning` from the run's start until the crawl ends, then
  `:done`; `:failed` with an `error` when the scan gave up. `facts` holds
  the site-level facts (robots.txt, sitemap, speed…); `pages_read` counts
  the Scanned Pages read so far. Deleted with its run.
  """
  use Ecto.Schema

  alias Dirmoon.Research.Run
  alias Dirmoon.SiteScans.ScannedPage

  @statuses [:scanning, :done, :failed]

  schema "site_scans" do
    field :status, Ecto.Enum, values: @statuses, default: :scanning
    field :error, :string
    field :facts, :map, default: %{}
    field :pages_read, :integer, default: 0

    belongs_to :run, Run
    has_many :scanned_pages, ScannedPage, preload_order: [asc: :position, asc: :id]

    timestamps(type: :utc_datetime)
  end
end
