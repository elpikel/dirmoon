defmodule Dirmoon.Research do
  @moduledoc """
  Research Runs: starting, stopping and resuming them, reading them with their
  Steps, their API Cost, and live updates over PubSub.

  Every function that reads or changes a run by id takes the `Scope` and only
  sees the Scope's Account's runs (ADR-0001); a foreign id is not found.

  Subscribers to a run (`subscribe/1`) receive `{:run_updated, run_id}` when
  the run or one of its Steps changes status, and
  `{:run_progress, run_id, progress}` from `broadcast_progress/2`.
  """

  import Ecto.Query

  alias Dirmoon.Accounts.Scope
  alias Dirmoon.Repo
  alias Dirmoon.Research.ApiRequest
  alias Dirmoon.Research.Pipeline
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.RunStep
  alias Dirmoon.Research.Steps

  @list_limit 50
  @cancellable_job_states ~w(available scheduled retryable)

  @doc """
  A changeset of a new run's input, for the form.
  """
  def change_run(%Scope{} = scope, attrs \\ %{}) do
    scope
    |> new_run()
    |> Run.changeset(attrs)
  end

  @doc """
  Starts a run in the Scope's Account: the run, running, with its nine Steps
  waiting, and Step 1 enqueued, all in one transaction.
  """
  def start_run(%Scope{} = scope, attrs) do
    Repo.transact(fn ->
      with {:ok, run} <- scope |> change_run(attrs) |> Repo.insert() do
        insert_waiting_steps(run)
        :ok = Pipeline.advance(run)
        {:ok, run}
      end
    end)
  end

  @doc """
  The Scope's Account's run with the given id, its Steps in order, or nil.
  """
  def get_run(%Scope{} = scope, id) do
    case Ecto.Type.cast(:id, id) do
      {:ok, run_id} ->
        scope
        |> account_runs_query()
        |> where([run: run], run.id == ^run_id)
        |> preload(steps: ^RunStep.ordered_by_number())
        |> Repo.one()

      :error ->
        nil
    end
  end

  @doc """
  The Scope's Account's latest #{@list_limit} runs, newest first, each with
  its Steps in order (so `Run.results_ready?/1` can be asked of it).
  """
  def list_runs(%Scope{} = scope) do
    scope
    |> account_runs_query()
    |> order_by([run: run], desc: run.inserted_at, desc: run.id)
    |> limit(@list_limit)
    |> preload(steps: ^RunStep.ordered_by_number())
    |> Repo.all()
  end

  @doc """
  Stops a running run and cancels its jobs that haven't started. Takes the
  run lock (`lock_run!/1`) first and checks the status on the locked row.

  Returns `{:error, :not_found}` for an id outside the Scope's Account and
  `{:error, :not_running}` for a run that isn't running.
  """
  def stop_run(%Scope{} = scope, id) do
    with {:ok, run} <- fetch_run(scope, id),
         {:ok, stopped_run} <- Repo.transact(fn -> stop_locked(run) end) do
      broadcast_run_updated(stopped_run)
      {:ok, stopped_run}
    end
  end

  @doc """
  Resumes a stopped or failed run: failed and interrupted Steps wait again,
  the run is running, and the first Step that isn't done or skipped is
  enqueued. Steps already done or skipped are not run again. A Step 8 or 9
  the User asked for that was queued or interrupted is enqueued again; one
  that failed is not (its page was put back), and the run settles. Takes the
  run lock (`lock_run!/1`) first and checks the status on the locked row.

  Returns `{:error, :not_found}` for an id outside the Scope's Account and
  `{:error, :not_resumable}` for a run that isn't stopped or failed.
  """
  def resume_run(%Scope{} = scope, id) do
    with {:ok, run} <- fetch_run(scope, id),
         {:ok, resumed_run} <- Repo.transact(fn -> resume_locked(run) end) do
      broadcast_run_updated(resumed_run)
      {:ok, resumed_run}
    end
  end

  @doc """
  The run's API Cost in USD: the sum of its recorded paid requests.
  """
  def run_cost(%Run{id: run_id}) do
    ApiRequest
    |> from(as: :api_request)
    |> where([api_request: api_request], api_request.run_id == ^run_id)
    |> select([api_request: api_request], coalesce(sum(api_request.cost), 0))
    |> Repo.one()
  end

  @doc """
  The API Costs in USD of several runs already resolved through the Scope,
  in one grouped query: a map of run id to cost, zero for a run with no
  recorded requests.
  """
  def run_costs(runs) when is_list(runs) do
    run_ids = Enum.map(runs, fn %Run{id: run_id} -> run_id end)

    recorded_costs =
      ApiRequest
      |> from(as: :api_request)
      |> where([api_request: api_request], api_request.run_id in ^run_ids)
      |> group_by([api_request: api_request], api_request.run_id)
      |> select([api_request: api_request], %{run_id: api_request.run_id, cost: sum(api_request.cost)})
      |> Repo.all()
      |> Map.new(fn %{run_id: run_id, cost: cost} -> {run_id, cost} end)

    Map.new(run_ids, &{&1, Map.get(recorded_costs, &1, Decimal.new(0))})
  end

  @doc """
  The estimated API Cost in USD of a run, before it starts, from the
  per-request prices in `config :dirmoon, :cost_estimates`: one keyword ideas
  request, one search volumes request for the country and one more for a
  city, one SERP request per checked Phrase (`serp_phrase_limit`) and the LLM
  allowance. The Mode doesn't change it: Search Console is free.
  """
  def estimated_cost(%{city?: city?}) when is_boolean(city?) do
    prices = Application.fetch_env!(:dirmoon, :cost_estimates)
    volume_requests = if city?, do: 2, else: 1

    Enum.reduce(
      [
        price(prices, :keyword_ideas),
        prices |> price(:search_volumes) |> Decimal.mult(volume_requests),
        prices |> price(:serp_top10) |> Decimal.mult(Application.fetch_env!(:dirmoon, :serp_phrase_limit)),
        price(prices, :llm_allowance)
      ],
      Decimal.new(0),
      &Decimal.add/2
    )
  end

  @doc """
  Whether the run is running now, read from the database, so a Step working
  through a long list sees a stop that happened since it loaded the run.
  """
  def running?(%Run{id: run_id}) do
    Run
    |> from(as: :run)
    |> where([run: run], run.id == ^run_id and run.status == ^:running)
    |> Repo.exists?()
  end

  @doc """
  Whether no Step of the run is at work or waiting for its job, read from the
  database: the run isn't running and none of its Steps is `:queued` or
  `:running` (`RunStep.in_progress?/1`). The precondition for starting a
  user-triggered Step (`Pipeline.start_step/2`): a stopped run whose Step 8
  or 9 is still queued must be resumed first, so one Step never runs
  underneath another.
  """
  def idle?(%Run{id: run_id}) do
    Run
    |> from(as: :run)
    |> where([run: run], run.id == ^run_id and run.status != ^:running)
    |> where(not exists(subquery(in_progress_steps_query())))
    |> Repo.exists?()
  end

  @doc """
  Locks the run's row `FOR UPDATE` and returns the locked `%Run{}`, read
  fresh, with its Steps in order (read after the lock). Must be called inside a transaction; the lock holds until it
  commits. Raises `Ecto.NoResultsError` for a missing id. Takes an id
  already resolved through the Scope or a pipeline job, never from params.
  """
  def lock_run!(run_id) do
    Run
    |> from(as: :run)
    |> where([run: run], run.id == ^run_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
    |> Repo.preload(steps: RunStep.ordered_by_number())
  end

  @doc """
  The stored output of the run's Step with the given number: `{:ok, output}`,
  or `:error` when that Step has no output. This is how a Step reads an
  earlier Step's output.
  """
  def step_output(%Run{id: run_id}, number) do
    RunStep
    |> from(as: :run_step)
    |> where([run_step: run_step], run_step.run_id == ^run_id and run_step.number == ^number)
    |> select([run_step: run_step], run_step.output)
    |> Repo.one()
    |> case do
      nil -> :error
      output -> {:ok, output}
    end
  end

  @doc """
  Stores the keyword API's location code for the run's city, once it is
  resolved. Never cast from params: only the Volumes Step sets it.
  """
  def put_city_location(%Run{} = run, city_location_code) when is_integer(city_location_code) do
    run
    |> Ecto.Changeset.change(city_location_code: city_location_code)
    |> Repo.update()
  end

  @doc """
  Subscribes the caller to a run's updates. Takes a run already resolved
  through the Scope (`get_run/2`).
  """
  def subscribe(%Run{} = run) do
    Phoenix.PubSub.subscribe(Dirmoon.PubSub, topic(run))
  end

  @doc """
  Tells subscribers about a Step's progress: `{:run_progress, run_id, progress}`.
  """
  def broadcast_progress(run_or_id, progress) when is_map(progress) do
    Phoenix.PubSub.broadcast(Dirmoon.PubSub, topic(run_or_id), {:run_progress, run_id(run_or_id), progress})
  end

  @doc """
  Tells subscribers that the run or one of its Steps changed status:
  `{:run_updated, run_id}`.
  """
  def broadcast_run_updated(run_or_id) do
    Phoenix.PubSub.broadcast(Dirmoon.PubSub, topic(run_or_id), {:run_updated, run_id(run_or_id)})
  end

  defp new_run(%Scope{account: account}) do
    %Run{account_id: account.id, status: :running}
  end

  defp account_runs_query(%Scope{account: account}) do
    Run
    |> from(as: :run)
    |> where([run: run], run.account_id == ^account.id)
  end

  defp in_progress_steps_query do
    RunStep
    |> from(as: :run_step)
    |> where([run_step: run_step], run_step.run_id == parent_as(:run).id)
    |> where([run_step: run_step], run_step.status in ^RunStep.in_progress_statuses())
  end

  defp fetch_run(scope, id) do
    case get_run(scope, id) do
      %Run{} = run -> {:ok, run}
      nil -> {:error, :not_found}
    end
  end

  defp ensure_status(%Run{status: status}, allowed_statuses, error) do
    if status in allowed_statuses, do: :ok, else: {:error, error}
  end

  defp insert_waiting_steps(run) do
    now = DateTime.utc_now(:second)

    steps =
      Enum.map(Steps.numbers(), fn number ->
        %{run_id: run.id, number: number, status: :waiting, inserted_at: now, updated_at: now}
      end)

    Repo.insert_all(RunStep, steps)
  end

  defp stop_locked(%Run{id: run_id}) do
    locked_run = lock_run!(run_id)

    with :ok <- ensure_status(locked_run, [:running], :not_running) do
      stop_and_cancel_jobs(locked_run)
    end
  end

  defp resume_locked(%Run{id: run_id}) do
    locked_run = lock_run!(run_id)

    with :ok <- ensure_status(locked_run, [:stopped, :failed], :not_resumable) do
      resume(locked_run)
    end
  end

  defp stop_and_cancel_jobs(run) do
    stopped_run =
      run
      |> Ecto.Changeset.change(status: :stopped)
      |> Repo.update!()
      |> Repo.preload(steps: RunStep.ordered_by_number())

    Oban.Job
    |> from(as: :job)
    |> where([job: job], job.state in @cancellable_job_states)
    |> where([job: job], fragment("? @> ?", job.args, type(^%{run_id: run.id}, :map)))
    |> Oban.cancel_all_jobs()

    {:ok, stopped_run}
  end

  defp resume(run) do
    :ok = Pipeline.resume(run)

    {:ok, run |> Repo.reload!() |> Repo.preload(steps: RunStep.ordered_by_number())}
  end

  defp price(prices, request), do: prices |> Map.fetch!(request) |> Decimal.new()

  defp topic(run_or_id), do: "run:#{run_id(run_or_id)}"

  defp run_id(%Run{id: run_id}), do: run_id
  defp run_id(run_id), do: run_id
end
