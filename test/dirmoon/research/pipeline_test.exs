defmodule Dirmoon.Research.PipelineTest do
  use Dirmoon.DataCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  import Mox

  alias Dirmoon.Pages.Page
  alias Dirmoon.Research
  alias Dirmoon.Research.Pipeline
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.RunStep
  alias Dirmoon.Workers.FetchCurrentPositions
  alias Dirmoon.Workers.FetchVolumes
  alias Dirmoon.Workers.PublishPage
  alias Dirmoon.Workers.ScoreNiches
  alias Dirmoon.Workers.WriteBrief

  test "advancing enqueues the next waiting Step" do
    run = insert(:run, steps: build_run_steps(%{1 => :done, 2 => :done}))

    assert :ok = Pipeline.advance(run)

    assert [%{worker: "Dirmoon.Workers.FetchVolumes", args: %{"run_id" => run_id}}] = all_enqueued()
    assert run_id == run.id
  end

  test "advancing while a Step is still running enqueues nothing" do
    run = insert(:run, steps: build_run_steps(%{1 => :done, 2 => :running}))

    assert :ok = Pipeline.advance(run)

    assert all_enqueued() == []
  end

  test "advancing a running run whose next Step failed enqueues nothing" do
    run = insert(:run, steps: build_run_steps(%{1 => :done, 2 => :failed}))

    assert :ok = Pipeline.advance(run)

    assert all_enqueued() == []
  end

  test "advancing a New Idea run past Step 5 marks Step 6 skipped" do
    run = insert(:run, mode: :new_idea, steps: build_run_steps(done_through(5)))

    :ok = Pipeline.advance(run)

    assert %RunStep{status: :skipped, result: "Nowy pomysł, nie ma jeszcze strony"} = step(run, 6)
  end

  test "advancing a New Idea run past Step 5 enqueues Step 7" do
    run = insert(:run, mode: :new_idea, steps: build_run_steps(done_through(5)))

    :ok = Pipeline.advance(run)

    assert_enqueued(worker: ScoreNiches, args: %{run_id: run.id})
    refute_enqueued(worker: FetchCurrentPositions)
  end

  test "advancing an Existing Site run past Step 5 enqueues Step 6" do
    run = insert(:run, mode: :existing_site, domain: "kkadwokat.pl", steps: build_run_steps(done_through(5)))

    :ok = Pipeline.advance(run)

    assert_enqueued(worker: FetchCurrentPositions, args: %{run_id: run.id})
    assert step(run, 6).status == :waiting
  end

  test "after Step 7 the run awaits a Niche choice" do
    run = insert(:run, steps: build_run_steps(done_through(7)))

    :ok = Pipeline.advance(run)

    assert Repo.reload!(run).status == :awaiting_choice
  end

  test "after Step 7 no Step is enqueued" do
    run = insert(:run, steps: build_run_steps(done_through(7)))

    :ok = Pipeline.advance(run)

    assert all_enqueued() == []
  end

  test "advancing a stopped run enqueues nothing" do
    run = insert(:run, status: :stopped, steps: build_run_steps(%{1 => :done}))

    :ok = Pipeline.advance(run)

    assert all_enqueued() == []
  end

  test "advancing twice enqueues the next Step once" do
    run = insert(:run, steps: build_run_steps(%{1 => :done, 2 => :done}))

    :ok = Pipeline.advance(run)
    :ok = Pipeline.advance(run)

    assert [_job] = all_enqueued(worker: FetchVolumes)
  end

  test "enqueueing Step 8 sets the run running and enqueues the brief writer" do
    run = insert(:run, status: :awaiting_choice, steps: build_run_steps(done_through(7)))

    assert {:ok, %Run{status: :running}} = Pipeline.enqueue_step(run, 8)

    assert_enqueued(worker: WriteBrief, args: %{run_id: run.id})
    assert Repo.reload!(run).status == :running
  end

  test "enqueueing Step 8 tells the run's subscribers" do
    run = insert(:run, status: :awaiting_choice, steps: build_run_steps(done_through(7)))
    run_id = run.id
    Research.subscribe(run)

    {:ok, _run} = Pipeline.enqueue_step(run, 8)

    assert_receive {:run_updated, ^run_id}
  end

  test "starting Step 8 sets the run running, queues the Step and enqueues the brief writer without telling subscribers" do
    run = insert(:run, status: :awaiting_choice, steps: build_run_steps(Map.put(done_through(7), 8, :done)))
    Research.subscribe(run)

    assert {:ok, %Run{status: :running}} = Pipeline.start_step(run, 8)

    assert_enqueued(worker: WriteBrief, args: %{run_id: run.id})
    assert %RunStep{status: :queued, result: nil} = step(run, 8)
    refute_receive {:run_updated, _run_id}
  end

  test "enqueueing Step 8 again clears its earlier output so it runs again" do
    steps = build_run_steps(Map.put(done_through(7), 8, :done))
    run = insert(:run, status: :awaiting_choice, steps: steps)

    {:ok, _run} = Pipeline.enqueue_step(run, 8)

    assert %RunStep{status: :queued, result: nil, output: nil} = step(run, 8)
  end

  test "starting Step 9 queues it until its job starts" do
    run = insert(:run, status: :done, steps: build_run_steps(done_through(9)))

    {:ok, _run} = Pipeline.start_step(run, 9)

    assert %RunStep{status: :queued, result: nil} = step(run, 9)
    assert_enqueued(worker: PublishPage, args: %{run_id: run.id})
  end

  test "a run with a queued Step 8 keeps running when it advances and its brief writer is enqueued" do
    run = insert(:run, status: :running, steps: build_run_steps(Map.put(done_through(7), 8, :queued)))

    :ok = Pipeline.advance(run)

    assert Repo.reload!(run).status == :running
    assert [%Oban.Job{worker: "Dirmoon.Workers.WriteBrief"}] = all_enqueued(queue: :pipeline)
  end

  test "a resumed run with Steps 8 and 9 both queued runs them one after the other and then settles" do
    run =
      insert(:run,
        status: :stopped,
        steps: 7 |> done_through() |> Map.put(8, :queued) |> Map.put(9, :queued) |> build_run_steps()
      )

    writing_page = insert(:page, run: run, status: :writing, brief: nil)
    publishing_page = insert(:page, run: run, status: :publishing)
    stub(Dirmoon.LLMMock, :structured, fn %{task: :brief} -> {:ok, brief_answer(), Decimal.new("0.01")} end)
    stub(Dirmoon.HostingMock, :create_site, fn _site -> {:ok, %{site_id: "netlify-site-1"}} end)
    stub(Dirmoon.HostingMock, :deploy, fn _deploy -> {:ok, %{url: "https://strona.example"}} end)

    :ok = Pipeline.resume(run)

    assert [%Oban.Job{worker: "Dirmoon.Workers.WriteBrief"}] = all_enqueued(queue: :pipeline)
    assert %{success: 2, failure: 0} = Oban.drain_queue(queue: :pipeline, with_recursion: true)
    assert %RunStep{status: :done} = step(run, 8)
    assert %RunStep{status: :done} = step(run, 9)
    assert Repo.reload!(run).status == :done
    assert Repo.get!(Page, writing_page.id).status == :ready
    assert Repo.get!(Page, publishing_page.id).status == :published
    assert all_enqueued(queue: :pipeline) == []
  end

  test "a run with a queued Step 9 keeps running when it advances" do
    run = insert(:run, status: :running, steps: build_run_steps(Map.put(done_through(8), 9, :queued)))

    :ok = Pipeline.advance(run)

    assert Repo.reload!(run).status == :running
  end

  test "after Step 8 the run awaits a choice again" do
    run = insert(:run, steps: build_run_steps(Map.put(done_through(7), 8, :done)))

    :ok = Pipeline.advance(run)

    assert Repo.reload!(run).status == :awaiting_choice
    refute_enqueued(worker: PublishPage)
  end

  test "after Step 9 the run is done" do
    run = insert(:run, steps: build_run_steps(done_through(9)))

    :ok = Pipeline.advance(run)

    assert Repo.reload!(run).status == :done
  end

  defp done_through(last_number) do
    Map.new(1..last_number, &{&1, :done})
  end

  defp brief_answer do
    %{
      "title" => "Tytuł strony testowej",
      "h1" => "Nagłówek testowy",
      "slug" => "strona-testowa",
      "breadcrumb" => "Strona główna / Strona testowa",
      "intro" => "Wstęp testowy. Drugie zdanie wstępu.",
      "cta_label" => "Zapytaj o termin",
      "fact_tiles" => [
        %{"label" => "Cena", "value" => "[CENA]"},
        %{"label" => "Telefon", "value" => "[TELEFON]"},
        %{"label" => "Obszar", "value" => "[OBSZAR]"}
      ],
      "sections" => [%{"question" => "Pytanie testowe?", "answer" => "Odpowiedź testowa."}],
      "short_answer" => "Odpowiedź testowa.",
      "phrases" => [],
      "primary_phrase" => nil
    }
  end

  defp step(run, number) do
    Repo.get_by!(RunStep, run_id: run.id, number: number)
  end
end
