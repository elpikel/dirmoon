defmodule Dirmoon.Workers.MatchSitePagesBatchTest do
  # Not async: it raises the page limit, which every scan reads.
  use Dirmoon.DataCase, async: false
  use Oban.Testing, repo: Dirmoon.Repo

  import Mox

  alias Dirmoon.Research
  alias Dirmoon.SiteScans.ScannedPage
  alias Dirmoon.Workers.MatchSitePages

  test "more pages than one request takes are sent fifty at a time, each numbered from one, all paid in the run's API Cost" do
    page_limit = Application.fetch_env!(:dirmoon, :site_scan_page_limit)
    Application.put_env(:dirmoon, :site_scan_page_limit, 60)
    on_exit(fn -> Application.put_env(:dirmoon, :site_scan_page_limit, page_limit) end)

    run =
      insert(:run,
        mode: :existing_site,
        domain: "hotel-dla-psow-testowy.example",
        steps: build_run_steps(Map.new(1..6, &{&1, :done}))
      )

    site_scan = insert(:site_scan, run: run, status: :done)
    niche = insert(:niche, run: run)

    pages =
      Enum.map(1..60, fn number ->
        insert(:scanned_page,
          site_scan: site_scan,
          url: "https://#{run.domain}/strona-#{number}",
          facts: %{"title" => "Strona #{number}", "main_headings" => [], "word_count" => 300}
        )
      end)

    expect(Dirmoon.LLMMock, :structured, 2, fn %{input: %{pages: batch}} ->
      assert Enum.map(batch, & &1.index) == Enum.to_list(1..length(batch))
      {:ok, %{"matches" => [%{"page" => 1, "niche_id" => niche.id}]}, Decimal.new("0.002")}
    end)

    assert :ok = perform_job(MatchSitePages, %{run_id: run.id})

    matched = ScannedPage |> Repo.all() |> Enum.filter(&(&1.cluster_id == niche.id)) |> Enum.map(& &1.id)
    assert Enum.sort(matched) == Enum.sort([Enum.at(pages, 0).id, Enum.at(pages, 50).id])
    assert Repo.reload!(site_scan).facts["matching"] == %{"done" => true, "pages" => 60, "matched" => 2}
    assert Decimal.equal?(Research.run_cost(run), Decimal.new("0.004"))
  end
end
