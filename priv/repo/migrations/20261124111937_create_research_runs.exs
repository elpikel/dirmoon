defmodule Dirmoon.Repo.Migrations.CreateResearchRuns do
  use Ecto.Migration

  def change do
    create table(:research_runs) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :description, :text, null: false
      add :mode, :string, null: false
      add :country_code, :string, null: false
      add :language_code, :string, null: false
      add :location_code, :integer, null: false
      add :city, :string
      add :city_location_code, :integer
      add :domain, :string
      add :priority_services, {:array, :string}, null: false, default: []
      add :status, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:research_runs, [:account_id, :inserted_at])

    create constraint(:research_runs, :research_runs_priority_services_at_most_five,
             check: "cardinality(priority_services) <= 5"
           )

    create constraint(:research_runs, :research_runs_domain_required_for_existing_site,
             check: "mode <> 'existing_site' OR domain IS NOT NULL"
           )

    create table(:run_steps) do
      add :run_id, references(:research_runs, on_delete: :delete_all), null: false
      add :number, :integer, null: false
      add :status, :string, null: false
      add :result, :text
      add :output, :map
      add :error, :text
      add :started_at, :utc_datetime
      add :finished_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:run_steps, [:run_id, :number])

    create constraint(:run_steps, :run_steps_number_between_one_and_nine,
             check: "number BETWEEN 1 AND 9"
           )

    create table(:api_requests) do
      add :run_id, references(:research_runs, on_delete: :delete_all), null: false
      add :service, :string, null: false
      add :operation, :string, null: false
      add :request_hash, :string, null: false
      add :request, :map, null: false
      add :response, :map, null: false
      add :cost, :decimal, precision: 12, scale: 6, null: false, default: 0

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:api_requests, [:run_id, :request_hash])

    create constraint(:api_requests, :api_requests_cost_not_negative, check: "cost >= 0")
  end
end
