defmodule Dirmoon.Repo.Migrations.AddMarketNamesToResearchRuns do
  use Ecto.Migration

  def up do
    alter table(:research_runs) do
      add :country_name, :string
      add :language_name, :string
    end

    execute """
    UPDATE research_runs SET
      country_name = CASE country_code
        WHEN 'US' THEN 'United States'
        WHEN 'GB' THEN 'United Kingdom'
        WHEN 'PL' THEN 'Poland'
        ELSE country_code
      END,
      language_name = CASE language_code
        WHEN 'en' THEN 'English'
        WHEN 'pl' THEN 'Polish'
        ELSE language_code
      END
    """

    alter table(:research_runs) do
      modify :country_name, :string, null: false
      modify :language_name, :string, null: false
    end
  end

  def down do
    alter table(:research_runs) do
      remove :country_name
      remove :language_name
    end
  end
end
