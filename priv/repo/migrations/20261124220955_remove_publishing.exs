defmodule Dirmoon.Repo.Migrations.RemovePublishing do
  use Ecto.Migration

  def up do
    execute "DELETE FROM run_steps WHERE number = 9"

    drop constraint(:run_steps, :run_steps_number_between_one_and_nine)

    create constraint(:run_steps, :run_steps_number_between_one_and_eight,
             check: "number BETWEEN 1 AND 8"
           )

    execute "UPDATE pages SET status = 'ready' WHERE status IN ('publishing', 'published')"

    alter table(:pages) do
      remove :published_url
      remove :hosting_site_id
    end

    execute "UPDATE research_runs SET status = 'awaiting_choice' WHERE status = 'done'"
  end

  def down do
    alter table(:pages) do
      add :published_url, :text
      add :hosting_site_id, :string
    end

    drop constraint(:run_steps, :run_steps_number_between_one_and_eight)

    create constraint(:run_steps, :run_steps_number_between_one_and_nine,
             check: "number BETWEEN 1 AND 9"
           )
  end
end
