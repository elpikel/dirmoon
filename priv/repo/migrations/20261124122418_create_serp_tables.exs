defmodule Dirmoon.Repo.Migrations.CreateSerpTables do
  use Ecto.Migration

  def change do
    create table(:serp_snapshots) do
      add :keyword_id, references(:keywords, on_delete: :delete_all), null: false
      add :location_code, :integer, null: false
      add :language_code, :string, null: false
      add :fetched_at, :utc_datetime, null: false
      add :results, :map, null: false, default: fragment("'[]'::jsonb")
      add :raw, :map, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:serp_snapshots, [:keyword_id, :location_code, :fetched_at])

    create table(:serp_assessments) do
      add :run_id, references(:research_runs, on_delete: :delete_all), null: false
      add :keyword_id, references(:keywords, on_delete: :restrict), null: false
      add :serp_snapshot_id, references(:serp_snapshots, on_delete: :restrict), null: false
      add :labels, :map, null: false, default: fragment("'[]'::jsonb")
      add :verdict, :string, null: false
      add :reused_snapshot, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:serp_assessments, [:run_id, :keyword_id])
    create index(:serp_assessments, [:keyword_id])
    create index(:serp_assessments, [:serp_snapshot_id])
  end
end
