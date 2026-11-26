defmodule Dirmoon.Workers.MatchSitePagesTest do
  use Dirmoon.DataCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  import Mox

  alias Dirmoon.Niches.Niche
  alias Dirmoon.Phrases.RunPhrase
  alias Dirmoon.Research
  alias Dirmoon.Research.ApiRequest
  alias Dirmoon.Research.Run
  alias Dirmoon.SiteScans
  alias Dirmoon.SiteScans.ScannedPage
  alias Dirmoon.SiteScans.SiteScan
  alias Dirmoon.Workers.MatchSitePages

  test "each readable page gets the one Niche the model chose for it from the run's own Niches" do
    site_scan = done_scan()
    boarding = niche(site_scan.run, ["hotel dla psów"])
    grooming = niche(site_scan.run, ["strzyżenie psów"])
    home = scanned_page(site_scan, "/")
    boarding_page = scanned_page(site_scan, "/hotel")
    grooming_page = scanned_page(site_scan, "/strzyzenie")

    expect(Dirmoon.LLMMock, :structured, 1, fn %{task: :match_pages} ->
      answer([match(1, nil), match(2, boarding.id), match(3, grooming.id)])
    end)

    assert :ok = perform_job(MatchSitePages, %{run_id: site_scan.run_id})

    assert niche_id(home) == nil
    assert niche_id(boarding_page) == boarding.id
    assert niche_id(grooming_page) == grooming.id
    assert matching(site_scan) == %{"done" => true, "pages" => 3, "matched" => 2}
  end

  test "subscribers are told when the pages are matched" do
    site_scan = done_scan()
    run_id = site_scan.run_id
    niche(site_scan.run, ["hotel dla psów"])
    scanned_page(site_scan, "/hotel")
    stub(Dirmoon.LLMMock, :structured, fn _request -> answer([]) end)
    :ok = SiteScans.subscribe(site_scan.run)

    :ok = perform_job(MatchSitePages, %{run_id: run_id})

    assert_received {:site_scan_updated, ^run_id}
  end

  test "the model is sent the Niches not rejected with up to five of their top Phrases, and only the site's own readable pages, by number" do
    site_scan = done_scan()
    kept = niche(site_scan.run, Enum.map(1..6, &"hotel dla psów #{&1}"))
    niche(site_scan.run, ["strzyżenie psów"], status: :rejected)
    long_title = String.duplicate("Hotel ", 100)
    scanned_page(site_scan, "/", %{"title" => long_title, "main_headings" => ["Hotel dla psów", "Drugi"]})
    scanned_page(site_scan, "/cennik?waluta=pln", %{"title" => nil, "main_headings" => []})
    scanned_page(site_scan, "/brak", %{}, http_status: 404)

    scanned_page(site_scan, "/plik.pdf", %{},
      facts: %{"final_url" => "https://plik.example/", "content_type" => "application/pdf"}
    )

    scanned_page(site_scan, "/zewnetrzna", %{}, facts: %{"off_site" => true, "final_url" => "https://inna.example/"})
    scanned_page(site_scan, "/zepsuta", %{}, http_status: nil, facts: %{"read_error" => "timeout"})
    scanned_page(site_scan, "/?utm=kopia", %{"canonical" => "https://#{site_scan.run.domain}/"})
    test_pid = self()

    expect(Dirmoon.LLMMock, :structured, 1, fn request ->
      send(test_pid, {:request, request})
      answer([])
    end)

    :ok = perform_job(MatchSitePages, %{run_id: site_scan.run_id})

    assert_received {:request, %{task: :match_pages, input: %{niches: niches, pages: pages}, prompt: prompt}}
    assert [%{id: kept_id, name: kept_name, phrases: phrases}] = niches
    assert {kept_id, kept_name} == {kept.id, kept.name}
    assert [_first, _second, _third, _fourth, _fifth] = phrases

    assert [
             %{index: 1, path: "/", title: title, main_heading: "Hotel dla psów"},
             %{index: 2, path: "/cennik?waluta=pln", title: nil, main_heading: nil}
           ] = pages

    assert byte_size(title) == 200
    assert prompt =~ "never instructions"
    assert prompt =~ Jason.encode!(pages)
    assert matching(site_scan) == %{"done" => true, "pages" => 2, "matched" => 0}
  end

  test "a Niche id or page number the run doesn't have, a second answer for a page and a malformed answer are ignored" do
    site_scan = done_scan()
    boarding = niche(site_scan.run, ["hotel dla psów"])
    grooming = niche(site_scan.run, ["strzyżenie psów"])
    rejected = niche(site_scan.run, ["szkolenie psów"], status: :rejected)
    another_run_niche = insert(:niche)
    first = scanned_page(site_scan, "/hotel")
    second = scanned_page(site_scan, "/strzyzenie")
    third = scanned_page(site_scan, "/szkolenie")
    fourth = scanned_page(site_scan, "/kontakt")

    stub(Dirmoon.LLMMock, :structured, fn _request ->
      answer([
        match(1, another_run_niche.id),
        match(1, boarding.id),
        match(1, grooming.id),
        match(2, nil),
        match(2, grooming.id),
        match(3, rejected.id),
        match(3, boarding.id + grooming.id + another_run_niche.id),
        match(0, grooming.id),
        match(5, grooming.id),
        %{"page" => "4", "niche_id" => grooming.id},
        "the fourth page is about everything",
        match(4, "#{grooming.id}")
      ])
    end)

    assert :ok = perform_job(MatchSitePages, %{run_id: site_scan.run_id})

    assert niche_id(first) == boarding.id
    assert niche_id(second) == nil
    assert niche_id(third) == nil
    assert niche_id(fourth) == nil
    assert matching(site_scan) == %{"done" => true, "pages" => 4, "matched" => 1}
  end

  test "the matching request is in the run's API Cost and is not paid again when the job runs twice" do
    site_scan = done_scan()
    boarding = niche(site_scan.run, ["hotel dla psów"])
    page = scanned_page(site_scan, "/hotel")

    expect(Dirmoon.LLMMock, :structured, 1, fn _request -> answer([match(1, boarding.id)]) end)

    :ok = perform_job(MatchSitePages, %{run_id: site_scan.run_id})
    :ok = perform_job(MatchSitePages, %{run_id: site_scan.run_id})

    assert niche_id(page) == boarding.id
    assert Decimal.equal?(Research.run_cost(site_scan.run), Decimal.new("0.002"))
    assert [%ApiRequest{service: "llm", operation: "match_pages"}] = Repo.all(ApiRequest)
  end

  test "matching again replaces the earlier matches of the scan's pages" do
    site_scan = done_scan()
    boarding = niche(site_scan.run, ["hotel dla psów"])
    grooming = niche(site_scan.run, ["strzyżenie psów"])
    first = scanned_page(site_scan, "/hotel", %{}, niche: grooming)
    second = scanned_page(site_scan, "/strzyzenie", %{}, niche: grooming)
    other_scan_page = insert(:scanned_page, niche: grooming)

    stub(Dirmoon.LLMMock, :structured, fn _request -> answer([match(1, boarding.id), match(2, nil)]) end)

    :ok = perform_job(MatchSitePages, %{run_id: site_scan.run_id})

    assert niche_id(first) == boarding.id
    assert niche_id(second) == nil
    assert niche_id(other_scan_page) == grooming.id
  end

  test "pages read but no Niches yet: the job asks nothing and looks again later" do
    site_scan = done_scan(steps: build_run_steps(Map.new(1..3, &{&1, :done})))
    page = scanned_page(site_scan, "/hotel")
    expect(Dirmoon.LLMMock, :structured, 0, fn _request -> answer([]) end)

    assert {:snooze, 20} = perform_job(MatchSitePages, %{run_id: site_scan.run_id})

    assert niche_id(page) == nil
    refute Map.has_key?(Repo.reload!(site_scan).facts, "matching")
  end

  test "Niches made but the pages still being read: the job asks nothing and looks again later" do
    site_scan = done_scan(scan_status: :scanning)
    niche(site_scan.run, ["hotel dla psów"])
    scanned_page(site_scan, "/hotel")
    expect(Dirmoon.LLMMock, :structured, 0, fn _request -> answer([]) end)

    assert {:snooze, 20} = perform_job(MatchSitePages, %{run_id: site_scan.run_id})

    assert %SiteScan{status: :scanning, facts: facts} = Repo.reload!(site_scan)
    refute Map.has_key?(facts, "matching")
  end

  test "a job that looked too early matches the pages once both sides are ready" do
    site_scan = done_scan(scan_status: :scanning)
    boarding = niche(site_scan.run, ["hotel dla psów"])
    page = scanned_page(site_scan, "/hotel")
    expect(Dirmoon.LLMMock, :structured, 1, fn _request -> answer([match(1, boarding.id)]) end)

    assert {:snooze, 20} = perform_job(MatchSitePages, %{run_id: site_scan.run_id})

    site_scan |> Ecto.Changeset.change(status: :done) |> Repo.update!()

    assert :ok = perform_job(MatchSitePages, %{run_id: site_scan.run_id})
    assert niche_id(page) == boarding.id
  end

  test "a run awaiting the owner's choice whose scan is still reading waits, then matches once the scan is done" do
    site_scan = done_scan(scan_status: :scanning, run_status: :awaiting_choice)
    boarding = niche(site_scan.run, ["hotel dla psów"])
    page = scanned_page(site_scan, "/hotel")
    expect(Dirmoon.LLMMock, :structured, 1, fn _request -> answer([match(1, boarding.id)]) end)

    assert {:snooze, 20} = perform_job(MatchSitePages, %{run_id: site_scan.run_id})

    site_scan |> Ecto.Changeset.change(status: :done) |> Repo.update!()

    assert :ok = perform_job(MatchSitePages, %{run_id: site_scan.run_id})
    assert niche_id(page) == boarding.id
  end

  test "a failed scan is never matched: the job stops waiting and stores nothing" do
    site_scan = done_scan(scan_status: :failed, steps: build_run_steps(Map.new(1..3, &{&1, :done})))
    niche(site_scan.run, ["hotel dla psów"])
    expect(Dirmoon.LLMMock, :structured, 0, fn _request -> answer([]) end)

    assert :ok = perform_job(MatchSitePages, %{run_id: site_scan.run_id})

    assert %SiteScan{status: :failed, facts: facts} = Repo.reload!(site_scan)
    refute Map.has_key?(facts, "matching")
  end

  test "a run stopped or failed before it made its Niches: the job stops waiting and stores nothing" do
    expect(Dirmoon.LLMMock, :structured, 0, fn _request -> answer([]) end)

    for status <- [:stopped, :failed] do
      site_scan = done_scan(run_status: status, steps: build_run_steps(Map.new(1..3, &{&1, :done})))
      scanned_page(site_scan, "/hotel")

      assert :ok = perform_job(MatchSitePages, %{run_id: site_scan.run_id})
      refute Map.has_key?(Repo.reload!(site_scan).facts, "matching")
    end
  end

  test "a run that failed after making its Niches still gets its pages matched" do
    site_scan = done_scan(run_status: :failed)
    boarding = niche(site_scan.run, ["hotel dla psów"])
    page = scanned_page(site_scan, "/hotel")
    expect(Dirmoon.LLMMock, :structured, 1, fn _request -> answer([match(1, boarding.id)]) end)

    assert :ok = perform_job(MatchSitePages, %{run_id: site_scan.run_id})

    assert niche_id(page) == boarding.id
  end

  test "a job that waited half an hour for both sides stops waiting and says the matching wasn't ready" do
    site_scan = done_scan(scan_status: :scanning)
    run_id = site_scan.run_id
    scanned_page(site_scan, "/hotel")
    expect(Dirmoon.LLMMock, :structured, 0, fn _request -> answer([]) end)
    :ok = SiteScans.subscribe(site_scan.run)

    assert {:snooze, 20} =
             perform_job(MatchSitePages, %{run_id: run_id}, inserted_at: minutes_ago(29))

    assert :ok = perform_job(MatchSitePages, %{run_id: run_id}, inserted_at: minutes_ago(30))

    assert matching(site_scan) == %{"done" => false, "reason" => "not_ready"}
    assert_received {:site_scan_updated, ^run_id}
  end

  test "an answer paid for whose matches could not be stored is replayed on the retry, not paid again" do
    site_scan = done_scan()
    boarding = niche(site_scan.run, ["hotel dla psów"])
    page = scanned_page(site_scan, "/hotel")

    expect(Dirmoon.LLMMock, :structured, 1, fn _request ->
      Repo.delete!(boarding)
      answer([match(1, boarding.id)])
    end)

    assert {:error, %Postgrex.Error{}} = perform_job(MatchSitePages, %{run_id: site_scan.run_id}, attempt: 1)
    assert niche_id(page) == nil
    assert [%ApiRequest{operation: "match_pages"}] = Repo.all(ApiRequest)

    restore_niche(boarding)

    assert :ok = perform_job(MatchSitePages, %{run_id: site_scan.run_id}, attempt: 2)
    assert niche_id(page) == boarding.id
    assert Decimal.equal?(Research.run_cost(site_scan.run), Decimal.new("0.002"))
  end

  test "a run without a scan has nothing to match" do
    run = insert(:run, steps: build_run_steps(Map.new(1..7, &{&1, :done})))
    expect(Dirmoon.LLMMock, :structured, 0, fn _request -> answer([]) end)

    assert :ok = perform_job(MatchSitePages, %{run_id: run.id})
  end

  test "no readable page, or no Niche on offer, is matching done with nothing matched and nothing asked" do
    expect(Dirmoon.LLMMock, :structured, 0, fn _request -> answer([]) end)

    without_pages = done_scan()
    niche(without_pages.run, ["hotel dla psów"])
    scanned_page(without_pages, "/brak", %{}, http_status: 404)

    without_niches = done_scan()
    niche(without_niches.run, ["hotel dla psów"], status: :rejected)
    scanned_page(without_niches, "/hotel")

    for site_scan <- [without_pages, without_niches] do
      assert :ok = perform_job(MatchSitePages, %{run_id: site_scan.run_id})
    end

    assert matching(without_pages) == %{"done" => true, "pages" => 0, "matched" => 0}
    assert matching(without_niches) == %{"done" => true, "pages" => 1, "matched" => 0}
  end

  test "Demo Data matches no page and says so, instead of presenting no match as fact" do
    site_scan = done_scan()
    grooming = niche(site_scan.run, ["strzyżenie psów"])
    page = scanned_page(site_scan, "/strzyzenie", %{}, niche: grooming)
    stub(Dirmoon.LLMMock, :structured, &Dirmoon.LLM.Demo.structured/1)

    assert :ok = perform_job(MatchSitePages, %{run_id: site_scan.run_id})

    assert matching(site_scan) == %{"done" => false, "reason" => "not_in_demo_data"}
    assert niche_id(page) == nil
  end

  test "without an LLM the matching is not done and says the LLM is not configured, without retrying" do
    site_scan = done_scan()
    niche(site_scan.run, ["hotel dla psów"])
    scanned_page(site_scan, "/hotel")
    expect(Dirmoon.LLMMock, :structured, 1, &Dirmoon.LLM.NotConfigured.structured/1)

    assert :ok = perform_job(MatchSitePages, %{run_id: site_scan.run_id}, attempt: 1)

    assert matching(site_scan) == %{"done" => false, "reason" => "not_configured"}
  end

  test "an LLM error is retried before the last attempt and nothing is stored" do
    site_scan = done_scan()
    niche(site_scan.run, ["hotel dla psów"])
    scanned_page(site_scan, "/hotel")
    stub(Dirmoon.LLMMock, :structured, fn _request -> {:error, "OpenAI: HTTP 500"} end)

    assert {:error, "OpenAI: HTTP 500"} = perform_job(MatchSitePages, %{run_id: site_scan.run_id}, attempt: 2)

    refute Map.has_key?(Repo.reload!(site_scan).facts, "matching")
    assert Repo.all(ApiRequest) == []
  end

  test "on the last attempt an LLM error stores the matching as failed, leaving the run and the scan as they were" do
    site_scan = done_scan()
    niche(site_scan.run, ["hotel dla psów"])
    scanned_page(site_scan, "/hotel")
    run_id = site_scan.run_id
    stub(Dirmoon.LLMMock, :structured, fn _request -> {:error, "OpenAI: HTTP 500"} end)
    :ok = SiteScans.subscribe(site_scan.run)

    assert {:cancel, "OpenAI: HTTP 500"} = perform_job(MatchSitePages, %{run_id: run_id}, attempt: 3)

    assert %SiteScan{status: :done, facts: %{"matching" => %{"done" => false, "reason" => "failed"}}} =
             Repo.reload!(site_scan)

    assert %Run{status: :running} = Repo.reload!(site_scan.run)
    assert_received {:site_scan_updated, ^run_id}
  end

  test "an answer without a list of matches is not stored, so the next attempt asks again" do
    site_scan = done_scan()
    boarding = niche(site_scan.run, ["hotel dla psów"])
    page = scanned_page(site_scan, "/hotel")

    expect(Dirmoon.LLMMock, :structured, 1, fn _request -> {:ok, %{"pages" => "all"}, Decimal.new("0.002")} end)

    assert {:error, "The model returned no list of matches"} =
             perform_job(MatchSitePages, %{run_id: site_scan.run_id}, attempt: 1)

    assert Repo.all(ApiRequest) == []

    expect(Dirmoon.LLMMock, :structured, 1, fn _request -> answer([match(1, boarding.id)]) end)

    assert :ok = perform_job(MatchSitePages, %{run_id: site_scan.run_id}, attempt: 2)
    assert niche_id(page) == boarding.id
  end

  test "a raise, exit or throw in the matching is retried, and on the last attempt stores the matching as failed" do
    for crash <- [fn -> raise "the model broke" end, fn -> exit(:model_gone) end, fn -> throw(:model_gave_up) end] do
      site_scan = done_scan()
      niche(site_scan.run, ["hotel dla psów"])
      scanned_page(site_scan, "/hotel")
      stub(Dirmoon.LLMMock, :structured, fn _request -> crash.() end)

      assert {:error, _reason} = perform_job(MatchSitePages, %{run_id: site_scan.run_id}, attempt: 1)
      refute Map.has_key?(Repo.reload!(site_scan).facts, "matching")

      assert {:cancel, _reason} = perform_job(MatchSitePages, %{run_id: site_scan.run_id}, attempt: 3)
      assert matching(site_scan) == %{"done" => false, "reason" => "failed"}
    end
  end

  test "a second trigger of the matching while the run's job waits, sleeps or runs enqueues nothing" do
    run = insert(:run, mode: :existing_site, domain: "strona-testowa.example")
    :ok = SiteScans.enqueue_matching(run)
    [first] = all_enqueued(worker: MatchSitePages)

    for state <- ~w(available scheduled executing retryable) do
      first |> Ecto.Changeset.change(state: state) |> Repo.update!()
      :ok = SiteScans.enqueue_matching(run)

      assert [_only_job] = Repo.all(Oban.Job)
    end

    first |> Ecto.Changeset.change(state: "completed") |> Repo.update!()
    :ok = SiteScans.enqueue_matching(run)

    assert [_first, _second] = Repo.all(Oban.Job)
  end

  test "a second matching job of a run after the first replays the stored answer instead of asking the model again" do
    site_scan = done_scan()
    boarding = niche(site_scan.run, ["hotel dla psów"])
    page = scanned_page(site_scan, "/hotel")

    expect(Dirmoon.LLMMock, :structured, 1, fn %{task: :match_pages} -> answer([match(1, boarding.id)]) end)

    assert :ok = perform_job(MatchSitePages, %{run_id: site_scan.run_id})
    assert :ok = perform_job(MatchSitePages, %{run_id: site_scan.run_id})

    assert niche_id(page) == boarding.id
    assert [%ApiRequest{operation: "match_pages"}] = Repo.all(ApiRequest)
  end

  test "the matching job runs on the site scan queue" do
    run = insert(:run, mode: :existing_site, domain: "strona-testowa.example")

    :ok = SiteScans.enqueue_matching(run)

    assert_enqueued(worker: MatchSitePages, args: %{run_id: run.id}, queue: :site_scan)
  end

  test "a New Idea run has no pages to match and nothing is enqueued" do
    run = insert(:run, mode: :new_idea)

    :ok = SiteScans.enqueue_matching(run)

    refute_enqueued(worker: MatchSitePages)
  end

  defp done_scan(options \\ []) do
    steps = Keyword.get(options, :steps, build_run_steps(Map.new(1..6, &{&1, :done})))

    run =
      insert(:run,
        mode: :existing_site,
        domain: "hotel-dla-psow-testowy.example",
        status: Keyword.get(options, :run_status, :running),
        steps: steps
      )

    insert(:site_scan, run: run, status: Keyword.get(options, :scan_status, :done))
  end

  defp niche(run, phrase_texts, attrs \\ []) do
    niche = insert(:niche, Keyword.merge([run: run], attrs))

    for text <- phrase_texts do
      phrase = insert(:phrase, phrase: unique_phrase_text(text), language_code: run.language_code)
      insert(:run_phrase, run: run, phrase: phrase, niche: niche)
    end

    niche
  end

  defp scanned_page(site_scan, path, facts \\ %{}, attrs \\ []) do
    page_facts =
      Map.merge(%{"title" => "Strona #{path}", "main_headings" => ["Nagłówek #{path}"], "word_count" => 300}, facts)

    insert(
      :scanned_page,
      Keyword.merge([site_scan: site_scan, url: "https://#{site_scan.run.domain}#{path}", facts: page_facts], attrs)
    )
  end

  defp match(page, niche_id), do: %{"page" => page, "niche_id" => niche_id}

  defp restore_niche(%Niche{id: niche_id, run_id: run_id} = niche) do
    niche |> Ecto.put_meta(state: :built) |> Repo.insert!()

    RunPhrase
    |> from(as: :run_phrase)
    |> where([run_phrase: run_phrase], run_phrase.run_id == ^run_id)
    |> Repo.update_all(set: [cluster_id: niche_id])
  end

  defp minutes_ago(minutes), do: DateTime.shift(DateTime.utc_now(), minute: -minutes)

  defp answer(matches), do: {:ok, %{"matches" => matches}, Decimal.new("0.002")}

  defp niche_id(%ScannedPage{} = page), do: Repo.reload!(page).cluster_id

  defp matching(site_scan), do: Repo.reload!(site_scan).facts["matching"]
end
