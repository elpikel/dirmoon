defmodule Dirmoon.Repo.Migrations.CreateSearchConsoleConnections do
  use Ecto.Migration

  def change do
    create table(:search_console_connections) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :google_email, :string, null: false
      add :encrypted_refresh_token, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:search_console_connections, [:account_id])
  end
end
