defmodule Dirmoon.Pages.Page do
  @moduledoc """
  A Page: the record that holds the Brief of one chosen Niche of a Research
  Run (dirmoon builds no page from it).
  Belongs to one Account; `account_id` is set from the run, never cast.

  `status` is `:writing` while Step 8 writes the Brief (at most one page of a
  run at a time, enforced by a partial unique index), `:ready` once the Brief
  is stored, and `:failed` with an `error` when Step 8 gave up. Only a
  `:ready` page's Brief can be edited.

  The page is deleted with its Niche: a Step 4 re-run deletes the run's
  Niches (`clusters`), and their pages go with them.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Dirmoon.Accounts.Account
  alias Dirmoon.Niches.Niche
  alias Dirmoon.Pages.Brief
  alias Dirmoon.Research.Run

  @statuses [:writing, :ready, :failed]

  schema "pages" do
    embeds_one :brief, Brief, on_replace: :update
    field :status, Ecto.Enum, values: @statuses, default: :writing
    field :error, :string

    belongs_to :account, Account
    belongs_to :run, Run
    belongs_to :niche, Niche, foreign_key: :cluster_id

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

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
