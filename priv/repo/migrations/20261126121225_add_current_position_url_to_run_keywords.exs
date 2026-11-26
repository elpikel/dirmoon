defmodule Dirmoon.Repo.Migrations.AddCurrentPositionUrlToRunKeywords do
  use Ecto.Migration

  def change do
    alter table(:run_keywords) do
      add :current_position_url, :text
    end
  end
end
