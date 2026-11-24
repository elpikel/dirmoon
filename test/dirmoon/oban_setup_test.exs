defmodule Dirmoon.ObanSetupTest.ReportingWorker do
  @moduledoc false
  use Oban.Worker, queue: :pipeline

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"test_pid" => encoded_pid}}) do
    encoded_pid
    |> Base.decode64!()
    |> :erlang.binary_to_term()
    |> send(:job_performed)

    :ok
  end
end

defmodule Dirmoon.ObanSetupTest do
  use Dirmoon.DataCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  alias Dirmoon.ObanSetupTest.ReportingWorker

  test "an enqueued job is stored without running" do
    args = %{"test_pid" => encoded_self()}

    {:ok, _job} = args |> ReportingWorker.new() |> Oban.insert()

    assert_enqueued(worker: ReportingWorker, args: args, queue: :pipeline)
    refute_received :job_performed
  end

  test "an enqueued job runs when the test drains the pipeline queue" do
    {:ok, _job} = %{"test_pid" => encoded_self()} |> ReportingWorker.new() |> Oban.insert()

    assert %{success: 1} = Oban.drain_queue(queue: :pipeline)
    assert_received :job_performed
    refute_enqueued(worker: ReportingWorker)
  end

  test "a job runs when the test performs it directly" do
    assert :ok = perform_job(ReportingWorker, %{"test_pid" => encoded_self()})
    assert_received :job_performed
  end

  defp encoded_self do
    self() |> :erlang.term_to_binary() |> Base.encode64()
  end
end
