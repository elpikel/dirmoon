defmodule Dirmoon.Repo.Migrations.CreatePages do
  use Ecto.Migration

  def change do
    create table(:pages) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :run_id, references(:research_runs, on_delete: :delete_all), null: false
      add :cluster_id, references(:clusters, on_delete: :delete_all), null: false
      add :brief, :map
      add :status, :string, null: false, default: "writing"
      add :error, :text
      add :published_url, :text
      add :hosting_site_id, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:pages, [:cluster_id])
    create index(:pages, [:account_id])
    create index(:pages, [:run_id])

    create unique_index(:pages, [:run_id],
             where: "status = 'writing'",
             name: :pages_one_writing_per_run_index
           )
  end
end
