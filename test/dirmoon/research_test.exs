defmodule Dirmoon.ResearchTest do
  use Dirmoon.DataCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  alias Dirmoon.Accounts.Scope
  alias Dirmoon.Billing
  alias Dirmoon.Research
  alias Dirmoon.Research.ApiRequest
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.RunStep
  alias Dirmoon.SiteScans.SiteScan
  alias Dirmoon.Workers.ExpandPhrases
  alias Dirmoon.Workers.FetchVolumes
  alias Dirmoon.Workers.GenerateSeeds
  alias Dirmoon.Workers.ScanSite
  alias Dirmoon.Workers.WriteBrief

  test "starting a run creates it in the user's Account with eight waiting Steps" do
    scope = scope_for(insert(:account))

    assert {:ok, run} = Research.start_run(scope, valid_run_attrs())

    assert run.account_id == scope.account.id
    assert run.status == :running
    assert run |> Repo.preload(:steps) |> Map.fetch!(:steps) |> Enum.map(& &1.status) == List.duplicate(:waiting, 8)
  end

  test "starting a run enqueues Step 1" do
    scope = scope_for(insert(:account))

    {:ok, run} = Research.start_run(scope, valid_run_attrs())

    assert_enqueued(worker: GenerateSeeds, args: %{run_id: run.id}, queue: :pipeline)
  end

  test "starting a run stores the chosen country and language with the country's location code and both names" do
    scope = scope_for(insert(:account))
    country = insert(:market_country)
    language = insert(:market_language)
    attrs = %{valid_run_attrs() | "country_code" => country.country_code, "language_code" => language.language_code}

    {:ok, run} = Research.start_run(scope, attrs)

    assert %Run{} = stored = Repo.reload!(run)
    assert stored.country_code == country.country_code
    assert stored.location_code == country.location_code
    assert stored.country_name == country.name
    assert stored.language_code == language.language_code
    assert stored.language_name == language.name
  end

  test "a posted location code is ignored: the run takes the stored country's" do
    scope = scope_for(insert(:account))
    country = insert(:market_country)
    attrs = Map.merge(valid_run_attrs(), %{"country_code" => country.country_code, "location_code" => "1"})

    {:ok, run} = Research.start_run(scope, attrs)

    assert run.location_code == country.location_code
  end

  test "a run without a description is rejected with an error on the description" do
    scope = scope_for(insert(:account))

    assert {:error, changeset} = Research.start_run(scope, %{valid_run_attrs() | "description" => "  "})

    assert %{description: [_message]} = errors_on(changeset)
    refute_enqueued(worker: GenerateSeeds)
  end

  test "an Existing Site run without a domain is rejected with an error on the domain" do
    scope = scope_for(insert(:account))
    attrs = Map.merge(valid_run_attrs(), %{"mode" => "existing_site", "domain" => ""})

    assert {:error, changeset} = Research.start_run(scope, attrs)

    assert %{domain: [_message]} = errors_on(changeset)
  end

  test "the domain of an Existing Site run is stored normalised" do
    scope = scope_for(insert(:account))
    attrs = Map.merge(valid_run_attrs(), %{"mode" => "existing_site", "domain" => "https://www.KKadwokat.pl/"})

    {:ok, run} = Research.start_run(scope, attrs)

    assert Repo.reload!(run).domain == "kkadwokat.pl"
  end

  test "starting an Existing Site research stores its Site Scan, scanning" do
    scope = scope_for(insert(:account))
    attrs = Map.merge(valid_run_attrs(), %{"mode" => "existing_site", "domain" => "kancelaria-testowa.example"})

    {:ok, run} = Research.start_run(scope, attrs)

    assert %SiteScan{status: :scanning} = Repo.get_by(SiteScan, run_id: run.id)
  end

  test "starting an Existing Site research enqueues its Site Scan's job" do
    scope = scope_for(insert(:account))
    attrs = Map.merge(valid_run_attrs(), %{"mode" => "existing_site", "domain" => "kancelaria-testowa.example"})

    {:ok, run} = Research.start_run(scope, attrs)

    site_scan = Repo.get_by!(SiteScan, run_id: run.id)
    assert_enqueued(worker: ScanSite, args: %{site_scan_id: site_scan.id}, queue: :site_scan)
  end

  test "a request paid for the research before it started is recorded on the run, in its API Cost" do
    scope = scope_for(insert(:account))
    attrs = Map.merge(valid_run_attrs(), %{"mode" => "existing_site", "domain" => "kancelaria-testowa.example"})

    {:ok, run} = Research.start_run(scope, attrs, ledger_entries: [draft_entry()])

    assert [%ApiRequest{service: "llm", operation: "describe_site"}] = Repo.all_by(ApiRequest, run_id: run.id)
    assert Decimal.equal?(Research.run_cost(run), Decimal.new("0.004"))
  end

  test "a rejected research records none of the requests paid before it" do
    scope = scope_for(insert(:account))
    attrs = Map.put(valid_run_attrs(), "description", " ")

    {:error, _changeset} = Research.start_run(scope, attrs, ledger_entries: [draft_entry()])

    assert Repo.all(ApiRequest) == []
  end

  test "a research started without paid requests has no API Cost yet" do
    scope = scope_for(insert(:account))

    {:ok, run} = Research.start_run(scope, valid_run_attrs(), [])

    assert Decimal.equal?(Research.run_cost(run), Decimal.new(0))
  end

  test "a malformed paid request stops the research from starting at all" do
    scope = scope_for(insert(:account))

    assert_raise FunctionClauseError, fn ->
      Research.start_run(scope, valid_run_attrs(), ledger_entries: [%{draft_entry() | response: "opis"}])
    end

    assert Repo.all(Run) == []
  end

  test "starting a New Idea research starts no Site Scan" do
    scope = scope_for(insert(:account))

    {:ok, run} = Research.start_run(scope, valid_run_attrs())

    assert Repo.get_by(SiteScan, run_id: run.id) == nil
    refute_enqueued(worker: ScanSite)
  end

  test "a rejected Existing Site research starts no Site Scan" do
    scope = scope_for(insert(:account))
    attrs = Map.merge(valid_run_attrs(), %{"mode" => "existing_site", "domain" => "not a domain"})

    {:error, _changeset} = Research.start_run(scope, attrs)

    assert Repo.aggregate(SiteScan, :count) == 0
    refute_enqueued(worker: ScanSite)
  end

  test "starting an Existing Site research writes nothing to the shared market tables" do
    scope = scope_for(insert(:account))
    attrs = Map.merge(valid_run_attrs(), %{"mode" => "existing_site", "domain" => "kancelaria-testowa.example"})
    shared_rows_before = shared_market_rows()

    {:ok, _run} = Research.start_run(scope, attrs)

    assert shared_market_rows() == shared_rows_before
  end

  test "a run with six Priority Services is rejected with an error on the Priority Services" do
    scope = scope_for(insert(:account))
    services = Enum.map(1..6, &"usługa #{&1}")

    assert {:error, changeset} = Research.start_run(scope, %{valid_run_attrs() | "priority_services" => services})

    assert %{priority_services: [_message]} = errors_on(changeset)
  end

  test "blank Priority Services are dropped" do
    scope = scope_for(insert(:account))
    services = ["rozwody", " ", "", "alimenty"]

    {:ok, run} = Research.start_run(scope, %{valid_run_attrs() | "priority_services" => services})

    assert run.priority_services == ["rozwody", "alimenty"]
  end

  test "stopping a running run cancels its pending jobs" do
    scope = scope_for(insert(:account))
    {:ok, run} = Research.start_run(scope, valid_run_attrs())

    assert {:ok, _run} = Research.stop_run(scope, run.id)

    refute_enqueued(worker: GenerateSeeds, args: %{run_id: run.id})
  end

  test "stopping a running run marks it stopped" do
    scope = scope_for(insert(:account))
    {:ok, run} = Research.start_run(scope, valid_run_attrs())

    assert {:ok, %Run{status: :stopped}} = Research.stop_run(scope, run.id)
    assert Repo.reload!(run).status == :stopped
  end

  test "stopping a run leaves other runs' jobs enqueued" do
    scope = scope_for(insert(:account))
    {:ok, run} = Research.start_run(scope, valid_run_attrs())
    {:ok, other_run} = Research.start_run(scope, valid_run_attrs())

    {:ok, _run} = Research.stop_run(scope, run.id)

    assert_enqueued(worker: GenerateSeeds, args: %{run_id: other_run.id})
  end

  test "stopping and then resuming a run returns it with its Steps in order each time" do
    account = insert(:account)
    run = insert(:run, account: account, status: :running, steps: build_run_steps(%{1 => :done, 2 => :running}))

    assert {:ok, %Run{status: :stopped, steps: stopped_steps}} = Research.stop_run(scope_for(account), run.id)
    assert Enum.map(stopped_steps, & &1.number) == Enum.to_list(1..8)

    assert {:ok, %Run{status: :running, steps: resumed_steps}} = Research.resume_run(scope_for(account), run.id)
    assert Enum.map(resumed_steps, & &1.number) == Enum.to_list(1..8)
    assert_enqueued(worker: ExpandPhrases, args: %{run_id: run.id})
  end

  test "a run that is already stopped can't be stopped again and stays stopped" do
    account = insert(:account)
    run = insert(:run, account: account, status: :stopped, steps: build_run_steps(%{1 => :done}))

    assert {:error, :not_running} = Research.stop_run(scope_for(account), run.id)
    assert Repo.reload!(run).status == :stopped
  end

  test "resuming a failed run enqueues the first Step that isn't done and doesn't rerun the done ones" do
    account = insert(:account)
    steps = build_run_steps(%{1 => :done, 2 => :done, 3 => :failed})
    run = insert(:run, account: account, status: :failed, steps: steps)

    assert {:ok, %Run{status: :running}} = Research.resume_run(scope_for(account), run.id)

    assert_enqueued(worker: FetchVolumes, args: %{run_id: run.id})
    refute_enqueued(worker: GenerateSeeds)
    refute_enqueued(worker: ExpandPhrases)
    assert step_statuses(run) == [:done, :done, :waiting, :waiting, :waiting, :waiting, :waiting, :waiting]
  end

  test "resuming a stopped run enqueues the Step that was running" do
    account = insert(:account)
    run = insert(:run, account: account, status: :stopped, steps: build_run_steps(%{1 => :done, 2 => :running}))

    assert {:ok, %Run{status: :running}} = Research.resume_run(scope_for(account), run.id)

    assert_enqueued(worker: ExpandPhrases, args: %{run_id: run.id})
    refute_enqueued(worker: GenerateSeeds)
  end

  test "resuming a run whose Step 8 failed doesn't retry it and awaits a choice" do
    account = insert(:account)
    run = insert(:run, account: account, status: :failed, steps: build_run_steps(Map.put(done_through(7), 8, :failed)))

    assert {:ok, %Run{status: :awaiting_choice}} = Research.resume_run(scope_for(account), run.id)

    assert all_enqueued() == []
    assert %RunStep{status: :waiting, error: nil} = Repo.get_by!(RunStep, run_id: run.id, number: 8)
  end

  test "resuming a run stopped while Step 8 was running enqueues the brief writer again" do
    account = insert(:account)
    run = insert(:run, account: account, status: :stopped, steps: build_run_steps(Map.put(done_through(7), 8, :running)))

    assert {:ok, %Run{status: :running}} = Research.resume_run(scope_for(account), run.id)

    assert_enqueued(worker: WriteBrief, args: %{run_id: run.id})
    assert %RunStep{status: :queued, started_at: nil} = Repo.get_by!(RunStep, run_id: run.id, number: 8)
  end

  test "resuming a run stopped before its queued Step 8 started enqueues the brief writer" do
    account = insert(:account)
    run = insert(:run, account: account, status: :stopped, steps: build_run_steps(Map.put(done_through(7), 8, :queued)))

    assert {:ok, %Run{status: :running}} = Research.resume_run(scope_for(account), run.id)

    assert [%Oban.Job{worker: "Dirmoon.Workers.WriteBrief"}] = all_enqueued(queue: :pipeline)
    assert Repo.get_by!(RunStep, run_id: run.id, number: 8).status == :queued
  end

  test "stopping a run keeps its queued Step queued" do
    account = insert(:account)
    run = insert(:run, account: account, status: :running, steps: build_run_steps(Map.put(done_through(7), 8, :queued)))

    {:ok, _run} = Research.stop_run(scope_for(account), run.id)

    assert Repo.get_by!(RunStep, run_id: run.id, number: 8).status == :queued
  end

  test "resuming a stopped run whose Step 8 was never started enqueues nothing and awaits a choice" do
    account = insert(:account)
    run = insert(:run, account: account, status: :stopped, steps: build_run_steps(done_through(7)))

    {:ok, _run} = Research.resume_run(scope_for(account), run.id)

    assert all_enqueued() == []
    assert Repo.reload!(run).status == :awaiting_choice
  end

  test "a run awaiting a choice can't be resumed" do
    account = insert(:account)
    run = insert(:run, account: account, status: :awaiting_choice, steps: build_run_steps(done_through(7)))

    assert {:error, :not_resumable} = Research.resume_run(scope_for(account), run.id)
    assert all_enqueued() == []
  end

  test "a running run can't be resumed" do
    account = insert(:account)
    run = insert(:run, account: account, status: :running, steps: build_run_steps(%{1 => :running}))

    assert {:error, :not_resumable} = Research.resume_run(scope_for(account), run.id)
    refute_enqueued(worker: GenerateSeeds)
  end

  test "a run's API Cost is the sum of its recorded request costs" do
    run = insert(:run)
    insert(:api_request, run: run, cost: Decimal.new("0.075"))
    insert(:api_request, run: run, cost: Decimal.new("0.0025"))
    insert(:api_request, cost: Decimal.new("9"))

    assert Decimal.equal?(Research.run_cost(run), Decimal.new("0.0775"))
  end

  test "a run with no recorded requests costs nothing" do
    run = insert(:run)

    assert Decimal.equal?(Research.run_cost(run), Decimal.new(0))
  end

  test "the API Costs of several runs come back per run, zero for a run with no requests" do
    costly_run = insert(:run)
    cheap_run = insert(:run)
    free_run = insert(:run)
    insert(:api_request, run: costly_run, cost: Decimal.new("0.075"))
    insert(:api_request, run: costly_run, cost: Decimal.new("0.0025"))
    insert(:api_request, run: cheap_run, cost: Decimal.new("0.01"))
    insert(:api_request, cost: Decimal.new("9"))

    costs = Research.run_costs([costly_run, cheap_run, free_run])

    assert costs |> Map.keys() |> Enum.sort() == Enum.sort([costly_run.id, cheap_run.id, free_run.id])
    assert Decimal.equal?(costs[costly_run.id], Decimal.new("0.0775"))
    assert Decimal.equal?(costs[cheap_run.id], Decimal.new("0.01"))
    assert Decimal.equal?(costs[free_run.id], Decimal.new(0))
  end

  test "getting a run returns it with its Steps in order" do
    account = insert(:account)
    run = insert(:run, account: account, steps: build_run_steps(%{1 => :done}))

    assert %Run{steps: steps} = Research.get_run(scope_for(account), run.id)
    assert Enum.map(steps, & &1.number) == Enum.to_list(1..8)
  end

  test "a run in another Account is not found" do
    run = insert(:run, steps: build_run_steps())

    assert Research.get_run(scope_for(insert(:account)), run.id) == nil
  end

  test "a malformed run id is not found" do
    assert Research.get_run(scope_for(insert(:account)), "not-an-id") == nil
  end

  test "a run id beyond the database's id range, or below it, is not found" do
    scope = scope_for(insert(:account))

    assert Research.get_run(scope, "99999999999999999999999") == nil
    assert Research.get_run(scope, "9223372036854775808") == nil
    assert Research.get_run(scope, "0") == nil
    assert Research.get_run(scope, "-1") == nil
    assert {:error, :not_found} = Research.stop_run(scope, "99999999999999999999999")
  end

  test "stopping a run in another Account is not found and leaves it running" do
    run = insert(:run, status: :running, steps: build_run_steps(%{1 => :running}))

    assert {:error, :not_found} = Research.stop_run(scope_for(insert(:account)), run.id)
    assert Repo.reload!(run).status == :running
  end

  test "resuming a run in another Account is not found and changes nothing" do
    run = insert(:run, status: :failed, steps: build_run_steps(%{1 => :failed}))

    assert {:error, :not_found} = Research.resume_run(scope_for(insert(:account)), run.id)
    assert Repo.reload!(run).status == :failed
    assert hd(step_statuses(run)) == :failed
    refute_enqueued(worker: GenerateSeeds)
  end

  test "listing runs returns the Account's runs newest first" do
    account = insert(:account)
    older = insert(:run, account: account, inserted_at: ~U[2026-11-01 10:00:00Z])
    newer = insert(:run, account: account, inserted_at: ~U[2026-11-20 10:00:00Z])
    insert(:run)

    assert account |> scope_for() |> Research.list_runs() |> Enum.map(& &1.id) == [newer.id, older.id]
  end

  test "listing runs with a count returns only that many of the Account's newest runs" do
    account = insert(:account)
    older = insert(:run, account: account, inserted_at: ~U[2026-11-01 10:00:00Z])
    newer = insert(:run, account: account, inserted_at: ~U[2026-11-20 10:00:00Z])
    newest = insert(:run, account: account, inserted_at: ~U[2026-11-21 10:00:00Z])
    insert(:run, inserted_at: ~U[2026-11-22 10:00:00Z])

    listed = account |> scope_for() |> Research.list_runs(2)

    assert Enum.map(listed, & &1.id) == [newest.id, newer.id]
    refute older.id in Enum.map(listed, & &1.id)
    assert Enum.all?(listed, &is_list(&1.steps))
  end

  test "subscribers to a run are told about progress" do
    run = insert(:run)
    :ok = Research.subscribe(run)

    :ok = Research.broadcast_progress(run, %{checked: 3, total: 30})

    assert_receive {:run_progress, run_id, %{checked: 3, total: 30}}
    assert run_id == run.id
  end

  test "progress broadcast by run id reaches the run's subscribers" do
    run = insert(:run)
    :ok = Research.subscribe(run)

    :ok = Research.broadcast_progress(run.id, %{checked: 1, total: 2})

    assert_receive {:run_progress, run_id, %{checked: 1, total: 2}}
    assert run_id == run.id
  end

  test "the form's changeset of a new run starts empty, with the Account set" do
    scope = scope_for(insert(:account))

    changeset = Research.change_run(scope)

    assert changeset.changes == %{}
    assert Ecto.Changeset.get_field(changeset, :account_id) == scope.account.id
  end

  test "an Existing Site run whose domain is only a scheme is rejected with an error on the domain" do
    scope = scope_for(insert(:account))
    attrs = Map.merge(valid_run_attrs(), %{"mode" => "existing_site", "domain" => "https://"})

    assert {:error, changeset} = Research.start_run(scope, attrs)

    assert %{domain: ["can't be blank"]} = errors_on(changeset)
  end

  test "a run in a country not in the stored countries is rejected with an error on the country" do
    scope = scope_for(insert(:account))

    assert {:error, changeset} = Research.start_run(scope, %{valid_run_attrs() | "country_code" => "T-unknown"})

    assert %{country_code: ["is not available"]} = errors_on(changeset)
    refute_enqueued(worker: GenerateSeeds)
  end

  test "a run in a language not in the stored languages is rejected with an error on the language" do
    scope = scope_for(insert(:account))

    assert {:error, changeset} = Research.start_run(scope, %{valid_run_attrs() | "language_code" => "x-unknown"})

    assert %{language_code: ["is not available"]} = errors_on(changeset)
    refute_enqueued(worker: GenerateSeeds)
  end

  test "a run without a language is rejected with an error on the language" do
    scope = scope_for(insert(:account))

    assert {:error, changeset} = Research.start_run(scope, %{valid_run_attrs() | "language_code" => ""})

    assert %{language_code: ["can't be blank"]} = errors_on(changeset)
  end

  test "a run without a country is rejected with an error on the country" do
    scope = scope_for(insert(:account))

    assert {:error, changeset} = Research.start_run(scope, %{valid_run_attrs() | "country_code" => ""})

    assert %{country_code: ["can't be blank"]} = errors_on(changeset)
  end

  test "a running run is running" do
    run = insert(:run, status: :running)

    assert Research.running?(run)
  end

  test "a run stopped since it was loaded is not running" do
    run = insert(:run, status: :running)

    Run
    |> from(as: :run)
    |> where([run: stored_run], stored_run.id == ^run.id)
    |> Repo.update_all(set: [status: :stopped])

    refute Research.running?(run)
  end

  test "a step's stored output is read for the run" do
    run = insert(:run, steps: build_run_steps(%{1 => :done}, %{1 => %{"seeds" => ["hotel dla psów"]}}))
    insert(:run, steps: build_run_steps(%{1 => :done}, %{1 => %{"seeds" => ["cudza fraza"]}}))

    assert {:ok, %{"seeds" => ["hotel dla psów"]}} = Research.step_output(run, 1)
  end

  test "a step without output has no output to read" do
    run = insert(:run, steps: build_run_steps(%{1 => :done}, %{1 => %{"seeds" => ["hotel dla psów"]}}))

    assert :error = Research.step_output(run, 2)
  end

  test "a resolved city location is stored on the run" do
    run = insert(:run, city: "Gdańsk")

    assert {:ok, %Run{city_location_code: 1_000_123}} = Research.put_city_location(run, 1_000_123)
    assert %Run{city_location_code: 1_000_123} = Repo.get!(Run, run.id)
  end

  test "the city location can't be set from the run form" do
    scope = scope_for(insert(:account))

    {:ok, run} = Research.start_run(scope, Map.put(valid_run_attrs(), "city_location_code", "1000123"))

    assert run.city_location_code == nil
  end

  test "locking a run inside a transaction returns that run as stored" do
    run = insert(:run, status: :awaiting_choice)

    assert {:ok, %Run{id: run_id, status: :awaiting_choice}} =
             Repo.transact(fn -> {:ok, Research.lock_run!(run.id)} end)

    assert run_id == run.id
  end

  test "locking a run that no longer exists raises" do
    run = insert(:run)
    Repo.delete!(run)

    assert_raise Ecto.NoResultsError, fn ->
      Repo.transact(fn -> {:ok, Research.lock_run!(run.id)} end)
    end
  end

  test "a running run is not idle" do
    run = insert(:run, status: :running, steps: build_run_steps(Map.put(done_through(7), 8, :running)))

    refute Research.idle?(run)
  end

  test "a stopped run with a queued Step is not idle" do
    run = insert(:run, status: :stopped, steps: build_run_steps(Map.put(done_through(7), 8, :queued)))

    refute Research.idle?(run)
  end

  test "a stopped run whose Steps are all finished or waiting is idle" do
    run = insert(:run, status: :stopped, steps: build_run_steps(%{1 => :done, 2 => :skipped}))

    assert Research.idle?(run)
  end

  test "a run awaiting a choice is idle" do
    run = insert(:run, status: :awaiting_choice, steps: build_run_steps(done_through(7)))

    assert Research.idle?(run)
  end

  test "a run whose Brief is written and that awaits a choice is idle" do
    run = insert(:run, status: :awaiting_choice, steps: build_run_steps(done_through(8)))

    assert Research.idle?(run)
  end

  test "the estimated cost adds phrase ideas, one volumes request, the SERP checks and the LLM allowance" do
    prices = Application.fetch_env!(:dirmoon, :cost_estimates)
    serp_phrase_limit = Application.fetch_env!(:dirmoon, :serp_phrase_limit)

    expected =
      prices.phrase_ideas
      |> Decimal.new()
      |> Decimal.add(Decimal.new(prices.search_volumes))
      |> Decimal.add(Decimal.mult(Decimal.new(prices.serp_top10), serp_phrase_limit))
      |> Decimal.add(Decimal.new(prices.llm_allowance))

    assert Decimal.equal?(Research.estimated_cost(%{city?: false, mode: :new_idea}), expected)
  end

  test "a city adds one more volumes request to the estimated cost" do
    prices = Application.fetch_env!(:dirmoon, :cost_estimates)

    difference =
      Decimal.sub(
        Research.estimated_cost(%{city?: true, mode: :new_idea}),
        Research.estimated_cost(%{city?: false, mode: :new_idea})
      )

    assert Decimal.equal?(difference, Decimal.new(prices.search_volumes))
  end

  test "an Existing Site run adds the ranked phrases request at its limit, the indexed page count, the Business Profile lookup and the site's linking sites" do
    prices = Application.fetch_env!(:dirmoon, :cost_estimates)
    ranked_phrases_limit = Application.fetch_env!(:dirmoon, :ranked_phrases_limit)

    difference =
      Decimal.sub(
        Research.estimated_cost(%{city?: false, mode: :existing_site}),
        Research.estimated_cost(%{city?: false, mode: :new_idea})
      )

    expected =
      prices.ranked_phrases_per_phrase
      |> Decimal.new()
      |> Decimal.mult(ranked_phrases_limit)
      |> Decimal.add(Decimal.new(prices.ranked_phrases_request))
      |> Decimal.add(Decimal.new(prices.indexed_page_count))
      |> Decimal.add(Decimal.new(prices.business_profile))
      |> Decimal.add(Decimal.new(prices.linking_sites_request))
      |> Decimal.add(Decimal.new(prices.linking_sites_per_domain))

    assert Decimal.equal?(difference, expected)
  end

  test "starting a research with one research left starts the run and records the Allowance it spent" do
    account = insert(:account, unpaid_access: false)
    allowance = insert(:allowance, account: account, researches: 1)

    assert {:ok, run} = Research.start_run(scope_for(account), valid_run_attrs())

    assert Repo.reload!(run).allowance_id == allowance.id
    assert_enqueued(worker: GenerateSeeds, args: %{run_id: run.id})
  end

  test "starting a research with no research left starts nothing and records no paid request" do
    account = insert(:account, unpaid_access: false)

    assert Research.start_run(scope_for(account), valid_run_attrs(), ledger_entries: [draft_entry()]) ==
             {:error, :no_researches_left}

    assert Repo.aggregate(Run, :count) == 0
    assert Repo.aggregate(ApiRequest, :count) == 0
    refute_enqueued(worker: GenerateSeeds)
  end

  test "starting a research with Unpaid Access starts the run and records no Allowance" do
    account = insert(:account, unpaid_access: true)

    assert {:ok, run} = Research.start_run(scope_for(account), valid_run_attrs())

    assert Repo.reload!(run).allowance_id == nil
  end

  test "an allowance id sent in the form's params is never stored on the run" do
    account = insert(:account, unpaid_access: true)
    other_allowance = insert(:allowance, researches: 1)

    {:ok, run} = Research.start_run(scope_for(account), Map.put(valid_run_attrs(), "allowance_id", other_allowance.id))

    assert Repo.reload!(run).allowance_id == nil
  end

  test "a rejected research spends nothing and shows its errors, even with no research left" do
    paying = insert(:account, unpaid_access: false)
    insert(:allowance, account: paying, researches: 1)
    used_up = insert(:account, unpaid_access: false)
    blank = %{valid_run_attrs() | "description" => "  "}

    assert {:error, %Ecto.Changeset{} = changeset} = Research.start_run(scope_for(paying), blank)
    assert %{description: ["can't be blank"]} = errors_on(changeset)
    assert Billing.researches_left(scope_for(paying)) == 1

    assert {:error, %Ecto.Changeset{} = changeset} = Research.start_run(scope_for(used_up), blank)
    assert %{description: ["can't be blank"]} = errors_on(changeset)
  end

  test "the last research left starts one run: a second start right after it is refused" do
    account = insert(:account, unpaid_access: false)
    insert(:allowance, account: account, researches: 1)
    scope = scope_for(account)

    assert {:ok, run} = Research.start_run(scope, valid_run_attrs())
    assert Research.start_run(scope, valid_run_attrs()) == {:error, :no_researches_left}

    assert Run |> Repo.all() |> Enum.map(& &1.id) == [run.id]
  end

  defp shared_market_rows do
    Map.new(["keywords", "keyword_metrics", "serp_snapshots"], fn table ->
      %Postgrex.Result{rows: rows} = Repo.query!("SELECT row_to_json(shared)::text FROM #{table} AS shared ORDER BY id")
      {table, rows}
    end)
  end

  defp draft_entry do
    %{
      service: "llm",
      operation: "describe_site",
      request: %{task: "describe_site", prompt: "Opisz stronę."},
      response: %{"description" => "Kancelaria notarialna w centrum miasta."},
      cost: Decimal.new("0.004")
    }
  end

  defp scope_for(account) do
    Scope.for_user(build(:user), account)
  end

  defp valid_run_attrs do
    country = insert(:market_country)
    language = insert(:market_language)

    %{
      "description" => "Kancelaria adwokacka w Gdańsku, prawo rodzinne i karne",
      "mode" => "new_idea",
      "country_code" => country.country_code,
      "language_code" => language.language_code,
      "city" => "Gdańsk",
      "domain" => "",
      "priority_services" => ["rozwody", "obrona karna"]
    }
  end

  defp done_through(last_number) do
    Map.new(1..last_number, &{&1, :done})
  end

  defp step_statuses(run) do
    RunStep
    |> from(as: :run_step)
    |> where([run_step: run_step], run_step.run_id == ^run.id)
    |> order_by([run_step: run_step], asc: run_step.number)
    |> select([run_step: run_step], run_step.status)
    |> Repo.all()
  end
end
