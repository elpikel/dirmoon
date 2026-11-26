defmodule Dirmoon.Repo.Migrations.AddFactsToCompetitorPages do
  use Ecto.Migration

  def change do
    alter table(:competitor_pages) do
      add :facts, :map
      add :linking_sites, :integer
    end

    create constraint(:competitor_pages, :competitor_pages_linking_sites_not_negative,
             check: "linking_sites >= 0"
           )
  end
end
