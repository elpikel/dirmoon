defmodule Dirmoon.Research.StepsTest do
  use Dirmoon.DataCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  alias Dirmoon.Research.RunStep
  alias Dirmoon.Research.Steps

  test "a Step's number is found by its key" do
    assert Steps.number!(:seeds) == 1
    assert Steps.number!(:competition) == 5
    assert Steps.number!(:brief_and_content) == 8
  end

  test "an unknown Step key raises" do
    assert_raise KeyError, fn -> Steps.number!(:no_such_step) end
  end

  test "each Step's worker runs the Step that Steps assigns to it" do
    for %{number: number, worker: worker} <- Steps.all() do
      statuses = Map.new(Steps.numbers(), &{&1, :waiting})
      only_this_step_done = Map.put(statuses, number, :done)
      run = insert(:run, status: :running, steps: build_run_steps(only_this_step_done))

      assert :ok = perform_job(worker, %{run_id: run.id})
      assert step_statuses(run) == only_this_step_done
    end
  end

  defp step_statuses(run) do
    RunStep
    |> from(as: :run_step)
    |> where([run_step: run_step], run_step.run_id == ^run.id)
    |> select([run_step: run_step], {run_step.number, run_step.status})
    |> Repo.all()
    |> Map.new()
  end
end
