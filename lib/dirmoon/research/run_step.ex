defmodule Dirmoon.Research.RunStep do
  @moduledoc """
  One of the eight Steps of a Research Run, with its status, its one-line
  result, its stored output and, when it failed, a readable error.

  A user-triggered Step (8) is `:queued` from the moment the User asks
  for it until its job starts, and again when it is interrupted, so a resume
  knows to run it; Steps 1–7 wait as `:waiting` instead.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Dirmoon.JsonSafe
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.Steps

  @statuses [:waiting, :queued, :running, :done, :skipped, :failed]
  @in_progress_statuses [:queued, :running]

  schema "run_steps" do
    field :number, :integer
    field :status, Ecto.Enum, values: @statuses
    field :result, :string
    field :output, :map
    field :error, :string
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime

    belongs_to :run, Run

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def in_progress_statuses, do: @in_progress_statuses

  def ordered_by_number do
    __MODULE__
    |> from(as: :run_step)
    |> order_by([run_step: run_step], asc: run_step.number)
  end

  def finished?(%__MODULE__{status: status}), do: status in [:done, :skipped]

  def in_progress?(%__MODULE__{status: status}), do: status in @in_progress_statuses

  def start_changeset(step) do
    change(step,
      status: :running,
      started_at: DateTime.utc_now(:second),
      finished_at: nil,
      error: nil
    )
  end

  def finish_changeset(step, %{status: status} = outcome) when status in [:done, :skipped] do
    change(step,
      status: status,
      result: outcome.result,
      output: outcome |> Map.get(:output) |> JsonSafe.encode(),
      error: nil,
      finished_at: DateTime.utc_now(:second)
    )
  end

  def fail_changeset(step, error) do
    change(step, status: :failed, error: error, finished_at: DateTime.utc_now(:second))
  end

  def reset_changeset(step), do: clear_changeset(step, :waiting)

  def queue_changeset(step), do: clear_changeset(step, :queued)

  def interrupt_changeset(%__MODULE__{number: number} = step) do
    if Steps.auto_chained?(number), do: reset_changeset(step), else: queue_changeset(step)
  end

  defp clear_changeset(step, status) do
    change(step,
      status: status,
      result: nil,
      output: nil,
      error: nil,
      started_at: nil,
      finished_at: nil
    )
  end
end
