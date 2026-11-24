defmodule Dirmoon.Workers.ScoreNichesTest do
  use Dirmoon.DataCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  alias Dirmoon.Niches.Niche
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.RunStep
  alias Dirmoon.Workers.ScoreNiches

  test "each niche gets a score from volume, cpc and competition with its components stored" do
    run = insert(:run, steps: build_run_steps(done_through(6)))
    leader = insert(:niche, run: run)
    unchecked = insert(:niche, run: run)
    checked = phrase_in_niche(run, leader, %{volume: 40, cpc: "2.00"})
    phrase_in_niche(run, unchecked, %{volume: 4, cpc: nil})
    insert(:serp_assessment, run: run, phrase: checked.phrase, labels: labels("blog", 10))

    assert :ok = perform_job(ScoreNiches, %{run_id: run.id})

    # leader: volume = log1p(40) / log1p(40) = 1, cpc = 1, weakness = 10 blogs of 10 = 1.0
    # score = 10 × (0.4 × 1 + 0.3 × 1 + 0.3 × 1.0) = 10.0
    assert %Niche{score: leader_score, score_components: leader_components} = Repo.get!(Niche, leader.id)
    assert Decimal.equal?(leader_score, Decimal.new("10.0"))
    assert rounded(leader_components) == %{"volume" => 1.0, "cpc" => 1.0, "weakness" => 1.0}

    # unchecked: volume = log1p(4) / log1p(40) = ln 5 / ln 41 ≈ 0.43339, cpc = 0, no SERP check so weakness = 0.5
    # score = 10 × (0.4 × 0.43339 + 0.3 × 0 + 0.3 × 0.5) ≈ 3.234 → 3.2
    assert %Niche{score: unchecked_score, score_components: unchecked_components} = Repo.get!(Niche, unchecked.id)
    assert Decimal.equal?(unchecked_score, Decimal.new("3.2"))
    assert rounded(unchecked_components) == %{"volume" => 0.43339, "cpc" => 0.0, "weakness" => 0.5}

    assert %RunStep{status: :done, result: "2 nisze ocenione, 1 warta zajęcia", output: output} = step(run, 7)
    assert %{"niches" => 2, "worth" => 1, "weights" => %{"volume" => 0.4, "cpc" => 0.3, "weakness" => 0.3}} = output
  end

  test "rejected phrases and rejected niches are left out of the scoring" do
    run = insert(:run, steps: build_run_steps(done_through(6)))
    leader = insert(:niche, run: run)
    other = insert(:niche, run: run)
    rejected_niche = insert(:niche, run: run, status: :rejected)
    phrase_in_niche(run, leader, %{volume: 40, cpc: "2.00"})
    phrase_in_niche(run, other, %{volume: 4, cpc: nil})
    phrase_in_niche(run, other, %{volume: 4000, cpc: "20.00", status: :rejected})
    phrase_in_niche(run, rejected_niche, %{volume: 8000, cpc: "30.00"})

    :ok = perform_job(ScoreNiches, %{run_id: run.id})

    assert Decimal.equal?(Repo.get!(Niche, leader.id).score, Decimal.new("8.5"))
    assert Decimal.equal?(Repo.get!(Niche, other.id).score, Decimal.new("3.2"))
    assert %Niche{score: nil, score_components: nil} = Repo.get!(Niche, rejected_niche.id)
  end

  test "scoring the run again gives the same scores" do
    run = insert(:run, steps: build_run_steps(done_through(6)))
    niches = insert_list(3, :niche, run: run)

    niches
    |> Enum.with_index(1)
    |> Enum.each(fn {niche, index} -> phrase_in_niche(run, niche, %{volume: index * 7, cpc: "#{index}.25"}) end)

    :ok = perform_job(ScoreNiches, %{run_id: run.id})
    first_scores = scores(niches)

    run |> step(7) |> RunStep.reset_changeset() |> Repo.update!()
    run |> Repo.reload!() |> Ecto.Changeset.change(status: :running) |> Repo.update!()

    :ok = perform_job(ScoreNiches, %{run_id: run.id})

    assert scores(niches) == first_scores
    assert Enum.all?(first_scores, &match?({%Decimal{}, %{}}, &1))
  end

  test "another run's niches keep their scores" do
    run = insert(:run, steps: build_run_steps(done_through(6)))
    phrase_in_niche(run, insert(:niche, run: run), %{volume: 12, cpc: "1.00"})
    other_niche = insert(:niche, score: Decimal.new("2.5"), score_components: %{"volume" => 0.1})
    phrase_in_niche(other_niche.run, other_niche, %{volume: 12, cpc: "1.00"})

    :ok = perform_job(ScoreNiches, %{run_id: run.id})

    assert %Niche{score: other_score, score_components: %{"volume" => 0.1}} = Repo.get!(Niche, other_niche.id)
    assert Decimal.equal?(other_score, Decimal.new("2.5"))
  end

  test "after scoring the run awaits a niche choice and no step is enqueued" do
    run = insert(:run, steps: build_run_steps(done_through(6)))
    phrase_in_niche(run, insert(:niche, run: run), %{volume: 12, cpc: "1.00"})

    :ok = perform_job(ScoreNiches, %{run_id: run.id})

    assert %Run{status: :awaiting_choice} = Repo.reload!(run)
    assert all_enqueued() == []
  end

  test "a run without niches fails the step with a readable reason on the last attempt" do
    run = insert(:run, steps: build_run_steps(done_through(6)))

    assert {:cancel, "Brak nisz do oceny"} = perform_job(ScoreNiches, %{run_id: run.id}, attempt: 3)

    assert %RunStep{status: :failed, error: "Brak nisz do oceny"} = step(run, 7)
    assert %Run{status: :failed} = Repo.reload!(run)
  end

  defp phrase_in_niche(run, niche, metrics) do
    phrase = insert(:phrase, phrase: unique_phrase_text("fraza do oceny"))

    insert(:volume,
      phrase: phrase,
      location_code: run.location_code,
      search_volume: metrics.volume,
      cpc: metrics.cpc && Decimal.new(metrics.cpc)
    )

    insert(:run_phrase, run: run, phrase: phrase, niche: niche, status: Map.get(metrics, :status, :kept))
  end

  defp labels(page_type, count), do: Enum.map(1..count, &%{"position" => &1, "page_type" => page_type})

  defp rounded(components), do: Map.new(components, fn {name, value} -> {name, Float.round(value, 5)} end)

  defp scores(niches) do
    niche_ids = Enum.map(niches, & &1.id)

    Niche
    |> from(as: :niche)
    |> where([niche: niche], niche.id in ^niche_ids)
    |> order_by([niche: niche], asc: niche.id)
    |> select([niche: niche], {niche.score, niche.score_components})
    |> Repo.all()
  end

  defp done_through(last_number), do: Map.new(1..last_number, &{&1, :done})

  defp step(run, number), do: Repo.get_by!(RunStep, run_id: run.id, number: number)
end
