defmodule Dirmoon.Repo.Migrations.CreateClusters do
  use Ecto.Migration

  def change do
    create table(:clusters) do
      add :run_id, references(:research_runs, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :intent, :text
      add :reading, :text
      add :score, :decimal, precision: 4, scale: 2
      add :score_components, :map
      add :status, :string, null: false, default: "proposed"
      add :position, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:clusters, [:run_id, :position])

    alter table(:run_keywords) do
      add :cluster_id, references(:clusters, on_delete: :nilify_all)
    end

    create index(:run_keywords, [:cluster_id])
  end
end
