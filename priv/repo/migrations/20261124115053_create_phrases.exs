defmodule Dirmoon.Repo.Migrations.CreatePhrases do
  use Ecto.Migration

  def change do
    create table(:keywords) do
      add :phrase, :text, null: false
      add :language_code, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:keywords, [:phrase, :language_code])

    create table(:keyword_metrics) do
      add :keyword_id, references(:keywords, on_delete: :delete_all), null: false
      add :location_code, :integer, null: false
      add :search_volume, :integer
      add :cpc, :decimal
      add :currency, :string, null: false
      add :monthly_searches, :map, null: false, default: fragment("'[]'::jsonb")
      add :fetched_at, :utc_datetime, null: false
      add :raw, :map, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:keyword_metrics, [:keyword_id, :location_code])

    create table(:run_keywords) do
      add :run_id, references(:research_runs, on_delete: :delete_all), null: false
      add :keyword_id, references(:keywords, on_delete: :restrict), null: false
      add :origin, :string, null: false
      add :status, :string, null: false, default: "kept"
      add :rejection_reason, :text
      add :current_position, :decimal

      timestamps(type: :utc_datetime)
    end

    create unique_index(:run_keywords, [:run_id, :keyword_id])
    create index(:run_keywords, [:keyword_id])
  end
end
