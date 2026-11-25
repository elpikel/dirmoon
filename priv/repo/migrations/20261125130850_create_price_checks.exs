defmodule Dirmoon.Repo.Migrations.CreatePriceChecks do
  use Ecto.Migration

  def change do
    create table(:price_checks) do
      add :run_id, references(:research_runs, on_delete: :delete_all), null: false
      add :cluster_id, references(:clusters, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "checking"
      add :error, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:price_checks, [:cluster_id])
    create index(:price_checks, [:run_id])

    create table(:competitor_pages) do
      add :price_check_id, references(:price_checks, on_delete: :delete_all), null: false
      add :google_position, :integer, null: false
      add :domain, :string, null: false
      add :url, :text, null: false
      add :read_url, :text
      add :outcome, :string, null: false, default: "waiting"
      add :offers, :map, null: false, default: fragment("'[]'::jsonb")

      timestamps(type: :utc_datetime)
    end

    create unique_index(:competitor_pages, [:price_check_id, :domain])
  end
end
