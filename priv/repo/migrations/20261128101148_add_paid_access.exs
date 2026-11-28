defmodule Dirmoon.Repo.Migrations.AddPaidAccess do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :unpaid_access, :boolean, null: false, default: false
      add :stripe_customer_id, :string
    end

    create unique_index(:accounts, [:stripe_customer_id])

    create table(:allowances) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :source, :string, null: false
      add :researches, :integer, null: false
      add :valid_from, :utc_datetime, null: false
      add :valid_until, :utc_datetime
      add :stripe_reference, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:allowances, [:stripe_reference])
    create index(:allowances, [:account_id])
    create constraint(:allowances, :allowances_researches_positive, check: "researches > 0")

    alter table(:research_runs) do
      add :allowance_id, references(:allowances, on_delete: :nilify_all)
    end

    create index(:research_runs, [:allowance_id])
  end
end
