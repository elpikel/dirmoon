defmodule Dirmoon.Repo.Migrations.RemoveOriginFromRunKeywords do
  use Ecto.Migration

  def up do
    alter table(:run_keywords) do
      remove :origin
    end
  end

  def down do
    alter table(:run_keywords) do
      add :origin, :string, null: false, default: "expansion"
    end
  end
end
