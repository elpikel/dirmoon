defmodule Dirmoon.Repo.Migrations.CreateSiteScans do
  use Ecto.Migration

  def change do
    create table(:site_scans) do
      add :run_id, references(:research_runs, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "scanning"
      add :error, :text
      add :facts, :map, null: false, default: %{}
      add :pages_read, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:site_scans, [:run_id])

    create table(:scanned_pages) do
      add :site_scan_id, references(:site_scans, on_delete: :delete_all), null: false
      add :url, :text, null: false
      add :http_status, :integer
      add :facts, :map, null: false, default: %{}
      add :cluster_id, references(:clusters, on_delete: :nilify_all)
      add :position, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:scanned_pages, [:site_scan_id, :url])
    create index(:scanned_pages, [:cluster_id])
  end
end
