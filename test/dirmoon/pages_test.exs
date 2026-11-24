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
  alias Dirmoon.Workers.PublishPage
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

    assert Enum.map(page_run.steps, & &1.number) == Enum.to_list(1..9)
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

  test "an edited brief field is saved, subscribers hear of it and the page renders the change" do
    account = insert(:account)
    page = insert(:page, run: insert(:run, account: account))
    scope = scope_for(account)
    Pages.subscribe(Pages.get_page(scope, page.id))

    params = brief_params(page.brief, %{"h1" => "Hotel dla psa na weekend"})

    assert {:ok, %Page{brief: %Brief{h1: "Hotel dla psa na weekend"}}} = Pages.update_brief(scope, page.id, params)
    assert_receive {:page_updated, page_id}
    assert page_id == page.id

    reloaded_page = Pages.get_page(scope, page.id)
    assert reloaded_page.brief.h1 == "Hotel dla psa na weekend"
    assert Pages.render(reloaded_page) =~ "Hotel dla psa na weekend"
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

  test "a page without a brief renders nothing" do
    account = insert(:account)
    page = insert(:page, run: insert(:run, account: account), status: :writing, brief: nil)

    assert account |> scope_for() |> Pages.get_page(page.id) |> Pages.render() == nil
  end

  test "publishing a ready page marks it publishing, runs the run again and enqueues step 9" do
    run = finished_run()
    page = insert(:page, run: run, status: :ready)

    assert {:ok, %Page{status: :publishing}} = Pages.publish(scope_for(run.account), page.id)

    assert Repo.get!(Page, page.id).status == :publishing
    assert Repo.get!(Run, run.id).status == :running
    assert Repo.get_by!(RunStep, run_id: run.id, number: 9).status == :queued
    assert_enqueued(worker: PublishPage, args: %{run_id: run.id})
  end

  test "publishing tells the page's subscribers and the run's subscribers once" do
    run = finished_run()
    page = insert(:page, run: run, status: :ready)
    scope = scope_for(run.account)
    Pages.subscribe(Pages.get_page(scope, page.id))
    Research.subscribe(run)
    page_id = page.id
    run_id = run.id

    {:ok, _page} = Pages.publish(scope, page.id)

    assert_receive {:page_updated, ^page_id}
    assert_receive {:run_updated, ^run_id}
    refute_receive {:run_updated, _run_id}
  end

  test "a published page of an existing site can be published again" do
    run = finished_run(%{mode: :existing_site, domain: "firma-testowa.example"})

    page =
      insert(:page, run: run, status: :published, published_url: "https://strona.example", hosting_site_id: "site")

    assert {:ok, %Page{status: :publishing, published_url: "https://strona.example"}} =
             Pages.publish(scope_for(run.account), page.id)

    assert_enqueued(worker: PublishPage, args: %{run_id: run.id})
  end

  test "publishing while a page of the run is being published enqueues no second step 9 job" do
    run = finished_run()
    page = insert(:page, run: run, status: :ready)
    other_page = insert(:page, run: run, status: :ready)
    scope = scope_for(run.account)

    {:ok, _page} = Pages.publish(scope, page.id)

    assert Pages.publish(scope, page.id) == {:error, :run_busy}
    assert Pages.publish(scope, other_page.id) == {:error, :run_busy}
    assert [_one_job] = all_enqueued(worker: PublishPage)
    assert Repo.get!(Page, other_page.id).status == :ready
  end

  test "a page can't be published while step 8 is writing another niche's brief" do
    run =
      insert(:run, status: :running, steps: 1..7 |> Map.new(&{&1, :done}) |> Map.put(8, :running) |> build_run_steps())

    page = insert(:page, run: run, status: :ready)

    assert Pages.publish(scope_for(run.account), page.id) == {:error, :run_busy}

    assert Repo.get!(Page, page.id).status == :ready
    assert Repo.get!(Run, run.id).status == :running
    refute_enqueued(worker: PublishPage)
  end

  test "a page can't be published on a stopped run whose step 8 is still queued until the run is resumed" do
    run = finished_run()
    niche = insert(:niche, run: run)
    ready_page = insert(:page, run: run, status: :ready)
    scope = scope_for(run.account)
    {:ok, writing_page} = Niches.choose(scope, niche.id)
    {:ok, _run} = Research.stop_run(scope, run.id)

    assert Pages.publish(scope, ready_page.id) == {:error, :run_busy}

    assert Repo.get!(Page, ready_page.id).status == :ready
    assert %RunStep{status: :done} = Repo.get_by!(RunStep, run_id: run.id, number: 9)
    refute_enqueued(worker: PublishPage)

    {:ok, _run} = Research.resume_run(scope, run.id)
    assert_enqueued(worker: WriteBrief, args: %{run_id: run.id})
    stub(Dirmoon.LLMMock, :structured, fn %{task: :brief} -> {:ok, brief_answer(), Decimal.new("0.01")} end)

    assert :ok = perform_job(WriteBrief, %{run_id: run.id})

    assert Repo.get!(Page, writing_page.id).status == :ready
    assert Repo.get!(Run, run.id).status == :done
    refute Enum.any?(Repo.preload(run, :steps, force: true).steps, &RunStep.in_progress?/1)
    assert {:ok, %Page{status: :publishing}} = Pages.publish(scope, ready_page.id)
    assert_enqueued(worker: PublishPage, args: %{run_id: run.id})
  end

  test "resuming a run stopped while writing a brief enqueues only the brief writer when publishing was refused meanwhile" do
    run = finished_run()
    niche = insert(:niche, run: run)
    ready_page = insert(:page, run: run, status: :ready)
    scope = scope_for(run.account)
    {:ok, _writing_page} = Niches.choose(scope, niche.id)
    {:ok, _run} = Research.stop_run(scope, run.id)
    {:error, :run_busy} = Pages.publish(scope, ready_page.id)

    {:ok, _run} = Research.resume_run(scope, run.id)

    assert [%Oban.Job{worker: "Dirmoon.Workers.WriteBrief"}] = all_enqueued(queue: :pipeline)
    assert Repo.get!(Page, ready_page.id).status == :ready
    assert Repo.get_by!(RunStep, run_id: run.id, number: 9).status == :done
  end

  test "another Account's page can't be published" do
    run = finished_run()
    page = insert(:page, run: run, status: :ready)

    assert Pages.publish(scope_for(insert(:account)), page.id) == {:error, :not_found}

    assert Repo.get!(Page, page.id).status == :ready
    assert Repo.get!(Run, run.id).status == :done
    refute_enqueued(worker: PublishPage)
  end

  test "a page without a written or valid brief can't be published" do
    run = finished_run()
    writing_page = insert(:page, run: run, status: :writing, brief: nil)
    invalid_page = insert(:page, run: run, status: :ready, brief: build(:brief, sections: []))
    scope = scope_for(run.account)

    assert Pages.publish(scope, writing_page.id) == {:error, :not_publishable}
    assert Pages.publish(scope, invalid_page.id) == {:error, :not_publishable}
    assert Repo.get!(Run, run.id).status == :done
    refute_enqueued(worker: PublishPage)
  end

  test "a page left publishing in a run that is no longer running is put back so it can be published again" do
    run = finished_run(%{status: :stopped})
    page = insert(:page, run: run, status: :publishing, published_url: "https://strona.example")

    assert {:ok, %Page{status: :publishing}} = Pages.publish(scope_for(run.account), page.id)
    assert_enqueued(worker: PublishPage, args: %{run_id: run.id})
  end

  test "the content file of a written page is its rendered html named after the slug" do
    run = finished_run()
    page = insert(:page, run: run, status: :ready, brief: build(:brief, slug: "hotel-dla-psa"))
    scope = scope_for(run.account)

    assert {:ok, %{filename: "hotel-dla-psa.html", html: html}} = Pages.content_file(scope, page.id)
    assert html == scope |> Pages.get_page(page.id) |> Pages.render()
  end

  test "a page being published or published has a content file too" do
    run = finished_run()
    publishing_page = insert(:page, run: run, status: :publishing)
    published_page = insert(:page, run: run, status: :published)
    scope = scope_for(run.account)

    assert {:ok, %{html: "<!DOCTYPE html>" <> _rest}} = Pages.content_file(scope, publishing_page.id)
    assert {:ok, %{html: "<!DOCTYPE html>" <> _rest}} = Pages.content_file(scope, published_page.id)
  end

  test "a content file without a usable slug is named strona.html" do
    run = finished_run()
    page = insert(:page, run: run, brief: build(:brief, slug: nil))

    assert {:ok, %{filename: "strona.html"}} = Pages.content_file(scope_for(run.account), page.id)
  end

  test "a page still being written has no content file and another Account's page is not found" do
    run = finished_run()
    writing_page = insert(:page, run: run, status: :writing, brief: nil)
    foreign_page = insert(:page, run: finished_run())

    assert Pages.content_file(scope_for(run.account), writing_page.id) == {:error, :not_ready}
    assert Pages.content_file(scope_for(run.account), foreign_page.id) == {:error, :not_found}
  end

  defp finished_run(attrs \\ %{}) do
    insert(:run, Map.merge(%{status: :done, steps: build_run_steps(Map.new(1..9, &{&1, :done}))}, attrs))
  end

  defp scope_for(account), do: Scope.for_user(build(:user), account)

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

  defp brief_params(%Brief{} = brief, changes) do
    Map.merge(
      %{
        "title" => brief.title,
        "h1" => brief.h1,
        "slug" => brief.slug,
        "intro" => brief.intro,
        "cta_label" => brief.cta_label,
        "short_answer" => brief.short_answer,
        "fact_tiles" => Enum.map(brief.fact_tiles, &%{"label" => &1.label, "value" => &1.value}),
        "sections" => Enum.map(brief.sections, &%{"question" => &1.question, "answer" => &1.answer})
      },
      changes
    )
  end
end
