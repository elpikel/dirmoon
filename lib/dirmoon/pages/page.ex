defmodule Dirmoon.Pages.Page do
  @moduledoc """
  A Produced Page for one chosen Niche of a Research Run, with its Brief.
  Belongs to one Account; `account_id` is set from the run, never cast.

  `status` is `:writing` while Step 8 writes the Brief (at most one page of a
  run at a time, enforced by a partial unique index), `:ready` once the Brief
  is stored, `:publishing` while Step 9 deploys it (at most one page of a
  run at a time, checked with the run locked), `:published` after Step 9,
  and `:failed` with an `error` when Step 8 gave up. A failed publish puts
  the page back to `:ready` or `:published` with the `error` set.

  The page is deleted with its Niche: a Step 4 re-run deletes the run's
  Niches (`clusters`), and their pages go with them.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Dirmoon.Accounts.Account
  alias Dirmoon.Niches.Niche
  alias Dirmoon.Pages.Brief
  alias Dirmoon.Research.Run

  @statuses [:writing, :ready, :publishing, :published, :failed]
  @editable_statuses [:ready, :published]
  @publishable_statuses [:ready, :published]
  @content_file_statuses [:ready, :publishing, :published]

  schema "pages" do
    embeds_one :brief, Brief, on_replace: :update
    field :status, Ecto.Enum, values: @statuses, default: :writing
    field :error, :string
    field :published_url, :string
    field :hosting_site_id, :string

    belongs_to :account, Account
    belongs_to :run, Run
    belongs_to :niche, Niche, foreign_key: :cluster_id

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def editable_statuses, do: @editable_statuses

  def publishable_statuses, do: @publishable_statuses

  def content_file_statuses, do: @content_file_statuses

  @doc """
  Sets the page's Brief from string- or atom-keyed Brief params, validated by
  `Brief.changeset/2`; a stored Brief is updated in place.
  """
  def brief_changeset(page, brief_params) do
    page
    |> cast(%{"brief" => brief_params}, [])
    |> cast_embed(:brief, with: &Brief.changeset/2, required: true)
  end
end
