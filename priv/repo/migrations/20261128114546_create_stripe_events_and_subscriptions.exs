defmodule Dirmoon.Repo.Migrations.CreateStripeEventsAndSubscriptions do
  use Ecto.Migration

  def change do
    create table(:stripe_events) do
      add :stripe_event_id, :string, null: false
      add :type, :string, null: false
      add :payload, :map, null: false
      add :processed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:stripe_events, [:stripe_event_id])

    create table(:subscriptions) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :stripe_subscription_id, :string, null: false
      add :status, :string, null: false
      add :current_period_start, :utc_datetime
      add :current_period_end, :utc_datetime
      add :ends_at, :utc_datetime
      add :stripe_updated_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:subscriptions, [:account_id])
    create unique_index(:subscriptions, [:stripe_subscription_id])
  end
end
