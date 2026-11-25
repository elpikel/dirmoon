defmodule Dirmoon.Repo.Migrations.CreateMarketLists do
  use Ecto.Migration

  def change do
    create table(:market_countries, primary_key: false) do
      add :country_code, :string, null: false
      add :location_code, :integer, null: false
      add :name, :string, null: false
      add :fetched_at, :utc_datetime, null: false
    end

    create unique_index(:market_countries, [:country_code])

    create table(:market_languages, primary_key: false) do
      add :language_code, :string, null: false
      add :name, :string, null: false
      add :fetched_at, :utc_datetime, null: false
    end

    create unique_index(:market_languages, [:language_code])
  end
end
