defmodule Dirmoon.Workers.PublishPageTest do
  use Dirmoon.DataCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  import Mox

  alias Dirmoon.Accounts.Scope
  alias Dirmoon.Pages
  alias Dirmoon.Pages.Page
  alias Dirmoon.Research
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.RunStep
  alias Dirmoon.Workers.PublishPage

  test "publishing a new idea page deploys its rendered html, stores the url and finishes step 9 and the run" do
    run = finished_run()
    page = insert(:page, run: run, brief: build(:brief, slug: "hotel-dla-psa"))
    scope = scope_for(run.account)
    expected_html = scope |> Pages.get_page(page.id) |> Pages.render()
    {:ok, _page} = Pages.publish(scope, page.id)

    expect(Dirmoon.HostingMock, :create_site, 1, fn %{site_name: "dirmoon-hotel-dla-psa"} ->
      {:ok, %{site_id: "netlify-site-1"}}
    end)

    expect(Dirmoon.HostingMock, :deploy, 1, fn %{site_id: "netlify-site-1", html: html} ->
      assert html == expected_html
      {:ok, %{url: "https://dirmoon-hotel-dla-psa.netlify.app"}}
    end)

    assert :ok = perform_job(PublishPage, %{run_id: run.id})

    assert %Page{
             status: :published,
             published_url: "https://dirmoon-hotel-dla-psa.netlify.app",
             hosting_site_id: "netlify-site-1",
             error: nil
           } = Repo.get!(Page, page.id)

    assert %RunStep{status: :done, result: "Opublikowano: https://dirmoon-hotel-dla-psa.netlify.app"} = step(run, 9)
    assert %Run{status: :done} = Repo.get!(Run, run.id)
  end

  test "a plausible domain on the page puts the plausible script for that domain in the deployed html" do
    run = finished_run()
    page = insert(:page, run: run, brief: build(:brief, plausible_domain: "hotel-dla-psa.example"))
    {:ok, _page} = Pages.publish(scope_for(run.account), page.id)
    test_process = self()

    expect(Dirmoon.HostingMock, :create_site, 1, fn _request -> {:ok, %{site_id: "netlify-site-1"}} end)

    expect(Dirmoon.HostingMock, :deploy, 1, fn %{html: html} ->
      send(test_process, {:deployed_html, html})
      {:ok, %{url: "https://hotel.netlify.app"}}
    end)

    :ok = perform_job(PublishPage, %{run_id: run.id})

    assert_receive {:deployed_html, html}
    assert html =~ ~s(data-domain="hotel-dla-psa.example")
    assert html =~ ~s(src="https://plausible.io/js/script.js")
  end

  test "publishing a published page again deploys anew to the same site without creating another" do
    run = finished_run()

    page =
      insert(:page,
        run: run,
        status: :published,
        published_url: "https://hotel.netlify.app",
        hosting_site_id: "netlify-site-1"
      )

    scope = scope_for(run.account)

    expect(Dirmoon.HostingMock, :create_site, 0, fn _request -> {:ok, %{site_id: "netlify-site-2"}} end)

    expect(Dirmoon.HostingMock, :deploy, 2, fn %{site_id: "netlify-site-1"} ->
      {:ok, %{url: "https://hotel.netlify.app"}}
    end)

    {:ok, _page} = Pages.publish(scope, page.id)
    :ok = perform_job(PublishPage, %{run_id: run.id})
    {:ok, _page} = Pages.publish(scope, page.id)
    assert :ok = perform_job(PublishPage, %{run_id: run.id})

    assert %Page{status: :published, hosting_site_id: "netlify-site-1"} = Repo.get!(Page, page.id)
    assert %Run{status: :done} = Repo.get!(Run, run.id)
    verify!()
  end

  test "without a netlify token step 9 fails with a readable reason and the page can still be downloaded" do
    run = finished_run()
    page = insert(:page, run: run, status: :ready)
    scope = scope_for(run.account)
    {:ok, _page} = Pages.publish(scope, page.id)

    expect(Dirmoon.HostingMock, :create_site, 1, fn _request -> {:error, :hosting_not_configured} end)

    assert {:cancel, :hosting_not_configured} = perform_job(PublishPage, %{run_id: run.id})

    assert %RunStep{status: :failed, error: "Brak tokenu Netlify"} = step(run, 9)
    assert %Page{status: :ready, error: "Brak tokenu Netlify", published_url: nil} = Repo.get!(Page, page.id)
    assert {:ok, %{html: "<!DOCTYPE html>" <> _rest}} = Pages.content_file(scope, page.id)
  end

  test "a publish that finally fails puts a published page back with its error and keeps its earlier url" do
    run = finished_run()

    page =
      insert(:page,
        run: run,
        status: :published,
        published_url: "https://hotel.netlify.app",
        hosting_site_id: "netlify-site-1"
      )

    {:ok, _page} = Pages.publish(scope_for(run.account), page.id)

    expect(Dirmoon.HostingMock, :deploy, 1, fn _request -> {:error, "Netlify: HTTP 500"} end)

    assert {:cancel, "Netlify: HTTP 500"} = perform_job(PublishPage, %{run_id: run.id}, attempt: 3)

    assert %Page{status: :published, error: "Netlify: HTTP 500", published_url: "https://hotel.netlify.app"} =
             Repo.get!(Page, page.id)

    assert %RunStep{status: :failed, error: "Netlify: HTTP 500"} = step(run, 9)
  end

  test "a publish that fails before the last attempt is retried and the page stays publishing with its new site" do
    run = finished_run()
    page = insert(:page, run: run, status: :ready)
    {:ok, _page} = Pages.publish(scope_for(run.account), page.id)

    expect(Dirmoon.HostingMock, :create_site, 1, fn _request -> {:ok, %{site_id: "netlify-site-1"}} end)
    expect(Dirmoon.HostingMock, :deploy, 1, fn _request -> {:error, "Netlify: HTTP 500"} end)

    assert {:error, "Netlify: HTTP 500"} = perform_job(PublishPage, %{run_id: run.id}, attempt: 1)
    assert %Page{status: :publishing, hosting_site_id: "netlify-site-1"} = Repo.get!(Page, page.id)
  end

  test "a retry after the new site's deploy failed deploys to that site and creates no other" do
    run = finished_run()
    page = insert(:page, run: run, status: :ready)
    {:ok, _page} = Pages.publish(scope_for(run.account), page.id)

    expect(Dirmoon.HostingMock, :create_site, 1, fn _request -> {:ok, %{site_id: "netlify-site-1"}} end)
    expect(Dirmoon.HostingMock, :deploy, 1, fn %{site_id: "netlify-site-1"} -> {:error, "Netlify: HTTP 500"} end)
    {:error, _reason} = perform_job(PublishPage, %{run_id: run.id}, attempt: 1)

    expect(Dirmoon.HostingMock, :deploy, 1, fn %{site_id: "netlify-site-1"} ->
      {:ok, %{url: "https://hotel.netlify.app"}}
    end)

    assert :ok = perform_job(PublishPage, %{run_id: run.id}, attempt: 2)

    assert %Page{status: :published, hosting_site_id: "netlify-site-1", published_url: "https://hotel.netlify.app"} =
             Repo.get!(Page, page.id)

    verify!()
  end

  test "a publish stopped before its job started is published once the run is resumed" do
    run = finished_run()
    page = insert(:page, run: run, status: :ready)
    scope = scope_for(run.account)
    {:ok, _page} = Pages.publish(scope, page.id)

    {:ok, _run} = Research.stop_run(scope, run.id)
    refute_enqueued(worker: PublishPage)

    {:ok, _run} = Research.resume_run(scope, run.id)
    assert_enqueued(worker: PublishPage, args: %{run_id: run.id})

    expect(Dirmoon.HostingMock, :create_site, 1, fn _request -> {:ok, %{site_id: "netlify-site-1"}} end)
    expect(Dirmoon.HostingMock, :deploy, 1, fn _request -> {:ok, %{url: "https://hotel.netlify.app"}} end)

    assert %{success: 1} = Oban.drain_queue(queue: :pipeline)

    assert %Page{status: :published, published_url: "https://hotel.netlify.app"} = Repo.get!(Page, page.id)
    assert %Run{status: :done} = Repo.get!(Run, run.id)
  end

  test "resuming a run whose step 9 finally failed retries nothing and the page can be published again" do
    run = finished_run()
    page = insert(:page, run: run, status: :ready)
    scope = scope_for(run.account)
    {:ok, _page} = Pages.publish(scope, page.id)

    expect(Dirmoon.HostingMock, :create_site, 1, fn _request -> {:error, :hosting_not_configured} end)

    assert %{cancelled: 1} = Oban.drain_queue(queue: :pipeline)
    assert %Page{status: :ready, error: "Brak tokenu Netlify"} = Repo.get!(Page, page.id)
    assert %Run{status: :failed} = Repo.get!(Run, run.id)

    assert {:ok, %Run{status: :awaiting_choice}} = Research.resume_run(scope, run.id)

    assert all_enqueued() == []
    assert %Page{status: :ready, error: "Brak tokenu Netlify"} = Repo.get!(Page, page.id)
    assert {:ok, %Page{status: :publishing}} = Pages.publish(scope, page.id)
    assert_enqueued(worker: PublishPage, args: %{run_id: run.id})
  end

  test "step 9 is skipped when no page of the run is being published" do
    run = insert(:run, status: :running, steps: build_run_steps(Map.new(1..8, &{&1, :done})))
    insert(:page, run: run, status: :ready)

    assert :ok = perform_job(PublishPage, %{run_id: run.id})

    assert %RunStep{status: :skipped, result: "Brak strony do publikacji"} = step(run, 9)
  end

  defp scope_for(account), do: Scope.for_user(build(:user), account)

  defp finished_run do
    insert(:run, status: :done, steps: build_run_steps(Map.new(1..9, &{&1, :done})))
  end

  defp step(run, number), do: Repo.get_by!(RunStep, run_id: run.id, number: number)
end
