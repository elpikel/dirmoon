defmodule Dirmoon.PagesTest do
  use Dirmoon.DataCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  import Mox

  alias Dirmoon.Accounts.Scope
  alias Dirmoon.Niches
  alias Dirmoon.Pages
  alias Dirmoon.Pages.Brief
  alias Dirmoon.Pages.Page
  alias Dirmoon.Research
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.RunStep
  alias Dirmoon.Workers.WriteBrief

  test "a page of the Scope's Account is found with its niche and run" do
    account = insert(:account)
    run = insert(:run, account: account)
    page = insert(:page, run: run)

    assert %Page{id: page_id, niche: niche, run: page_run} = Pages.get_page(scope_for(account), page.id)
    assert page_id == page.id
    assert niche.id == page.cluster_id
    assert page_run.id == run.id
  end

  test "a page's run comes with its Steps in order, so the screen can ask whether the run is choosable" do
    account = insert(:account)
    run = insert(:run, account: account, steps: Enum.reverse(build_run_steps()))
    page = insert(:page, run: run)

    %Page{run: page_run} = Pages.get_page(scope_for(account), page.id)

    assert Enum.map(page_run.steps, & &1.number) == Enum.to_list(1..8)
  end

  test "another Account's page or a malformed id is not found" do
    page = insert(:page, run: insert(:run))
    scope = scope_for(insert(:account))

    assert Pages.get_page(scope, page.id) == nil
    assert Pages.get_page(scope, "nie-liczba") == nil
  end

  test "pages are listed newest first and only for the Scope's Account" do
    account = insert(:account)
    run = insert(:run, account: account)
    older = insert(:page, run: run, inserted_at: ~U[2026-11-01 10:00:00Z])
    newer = insert(:page, run: run, inserted_at: ~U[2026-11-20 10:00:00Z])
    insert(:page, run: insert(:run))

    assert account |> scope_for() |> Pages.list_pages() |> Enum.map(& &1.id) == [newer.id, older.id]
  end

  test "an edited brief field is saved and subscribers hear of it" do
    account = insert(:account)
    page = insert(:page, run: insert(:run, account: account))
    scope = scope_for(account)
    Pages.subscribe(Pages.get_page(scope, page.id))

    params = brief_params(page.brief, %{"h1" => "Hotel dla psa na weekend"})

    assert {:ok, %Page{brief: %Brief{h1: "Hotel dla psa na weekend"}}} = Pages.update_brief(scope, page.id, params)
    assert_receive {:page_updated, page_id}
    assert page_id == page.id

    assert Pages.get_page(scope, page.id).brief.h1 == "Hotel dla psa na weekend"
  end

  test "the User's own contact values in an edited brief are kept as typed" do
    account = insert(:account)
    page = insert(:page, run: insert(:run, account: account))
    scope = scope_for(account)
    answer = "Zadzwoń pod 600 100 200, nocleg kosztuje 120 zł."

    params = brief_params(page.brief, %{"sections" => [%{"question" => "Jak zarezerwować?", "answer" => answer}]})

    assert {:ok, %Page{brief: %Brief{sections: [%Brief.Section{answer: ^answer}]}}} =
             Pages.update_brief(scope, page.id, params)
  end

  test "an invalid brief edit returns the changeset and saves nothing" do
    account = insert(:account)
    page = insert(:page, run: insert(:run, account: account))
    scope = scope_for(account)

    assert {:error, %Ecto.Changeset{valid?: false} = changeset} =
             Pages.update_brief(scope, page.id, brief_params(page.brief, %{"h1" => "", "slug" => "Zły Slug"}))

    assert %{h1: [_required], slug: [_format]} = errors_on(changeset)
    assert Repo.get!(Page, page.id).brief.h1 == page.brief.h1
  end

  test "another Account's brief can't be edited" do
    page = insert(:page, run: insert(:run))
    scope = scope_for(insert(:account))

    assert {:error, :not_found} =
             Pages.update_brief(scope, page.id, brief_params(page.brief, %{"h1" => "Cudzy nagłówek"}))

    assert Repo.get!(Page, page.id).brief.h1 == page.brief.h1
  end

  test "a brief still being written can't be edited" do
    account = insert(:account)
    page = insert(:page, run: insert(:run, account: account), status: :writing, brief: nil)

    assert {:error, :not_editable} = Pages.update_brief(scope_for(account), page.id, %{"h1" => "Nagłówek"})
    assert Repo.get!(Page, page.id).brief == nil
  end

  test "a stopped run whose step 8 is still queued writes the brief once resumed and then awaits a choice" do
    run = finished_run()
    niche = insert(:niche, run: run)
    scope = scope_for(run.account)
    {:ok, writing_page} = Niches.choose(scope, niche.id)
    {:ok, _run} = Research.stop_run(scope, run.id)

    {:ok, _run} = Research.resume_run(scope, run.id)

    assert [%Oban.Job{worker: "Dirmoon.Workers.WriteBrief"}] = all_enqueued(queue: :pipeline)
    stub(Dirmoon.LLMMock, :structured, fn %{task: :brief} -> {:ok, brief_answer(), Decimal.new("0.01")} end)

    assert :ok = perform_job(WriteBrief, %{run_id: run.id})

    assert Repo.get!(Page, writing_page.id).status == :ready
    assert Repo.get!(Run, run.id).status == :awaiting_choice
    refute Enum.any?(Repo.preload(run, :steps, force: true).steps, &RunStep.in_progress?/1)
  end

  test "a Brief stored with the removed page build's fields still loads, and saving it drops them" do
    account = insert(:account)
    page = insert(:page, run: insert(:run, account: account))
    scope = scope_for(account)

    removed_fields = %{
      "breadcrumb" => "Start",
      "cta_label" => "Zadzwoń",
      "nav_links" => ["Oferta"],
      "fact_tiles" => [%{"label" => "Cena", "value" => "[PRICE]"}],
      "plausible_domain" => "strona-testowa.example"
    }

    Repo.query!("UPDATE pages SET brief = brief || $2 WHERE id = $1", [page.id, removed_fields])

    assert %Page{brief: %Brief{h1: h1}} = Pages.get_page(scope, page.id)
    assert h1 == page.brief.h1

    assert {:ok, _page} = Pages.update_brief(scope, page.id, brief_params(page.brief, %{"h1" => "Nagłówek po zapisie"}))

    %Postgrex.Result{rows: [[stored_keys]]} =
      Repo.query!("SELECT array_agg(key ORDER BY key) FROM pages, jsonb_object_keys(brief) AS key WHERE id = $1", [
        page.id
      ])

    assert stored_keys -- Map.keys(removed_fields) == stored_keys
    assert "h1" in stored_keys
  end

  defp finished_run(attrs \\ %{}) do
    insert(:run, Map.merge(%{status: :awaiting_choice, steps: build_run_steps(Map.new(1..8, &{&1, :done}))}, attrs))
  end

  defp scope_for(account), do: Scope.for_user(build(:user), account)

  defp brief_answer do
    %{
      "title" => "Tytuł strony testowej",
      "h1" => "Nagłówek testowy",
      "slug" => "strona-testowa",
      "intro" => "Wstęp testowy. Drugie zdanie wstępu.",
      "sections" => [%{"question" => "Pytanie testowe?", "answer" => "Odpowiedź testowa."}],
      "short_answer" => "Odpowiedź testowa.",
      "phrases" => [],
      "primary_phrase" => nil
    }
  end

  defp brief_params(%Brief{} = brief, changes) do
    Map.merge(
      %{
        "title" => brief.title,
        "h1" => brief.h1,
        "slug" => brief.slug,
        "intro" => brief.intro,
        "short_answer" => brief.short_answer,
        "sections" => Enum.map(brief.sections, &%{"question" => &1.question, "answer" => &1.answer})
      },
      changes
    )
  end
end
