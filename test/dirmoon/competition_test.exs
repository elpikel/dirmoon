defmodule Dirmoon.CompetitionTest do
  use Dirmoon.DataCase, async: true

  alias Dirmoon.Competition
  alias Dirmoon.Competition.SerpAssessment
  alias Dirmoon.Competition.SerpSnapshot

  test "competition is weak when blogs, forums and directories hold most of the top 10" do
    labels = labels(blog: 3, forum: 2, directory: 1, direct_competitor: 4)

    assert Competition.verdict(labels) == :weak
  end

  test "competition is strong when direct competitors hold most of the top 10" do
    labels = labels(direct_competitor: 6, blog: 4)

    assert Competition.verdict(labels) == :strong
  end

  test "competition is strong when direct competitors hold five of the top 10" do
    labels = labels(direct_competitor: 5, blog: 3, portal: 2)

    assert Competition.verdict(labels) == :strong
  end

  test "competition is medium when neither weak page types nor direct competitors hold most of the top 10" do
    labels = labels(portal: 4, direct_competitor: 3, blog: 3)

    assert Competition.verdict(labels) == :medium
  end

  test "half of the top 10 held by weak page types is not a majority" do
    labels = labels(blog: 5, portal: 5)

    assert Competition.verdict(labels) == :medium
  end

  test "an empty top 10 is weak competition" do
    assert Competition.verdict([]) == :weak
  end

  test "who holds the top 10 names the two most common page types, the higher ranked first on a tie" do
    labels = labels(portal: 2, forum: 3, blog: 3, direct_competitor: 2)

    assert Competition.holders(labels) == "forums, guides and blogs"
  end

  test "who holds the top 10 names one page type when only one holds it" do
    assert Competition.holders(labels(direct_competitor: 10)) == "businesses like yours"
  end

  test "who holds an empty top 10 says there are no results" do
    assert Competition.holders([]) == "no results"
  end

  test "the first page lists the snapshot's results in position order with the name of each one's page type" do
    results = [
      %{"position" => 2, "url" => "https://drugi.example/", "domain" => "drugi.example", "title" => "Drugi"},
      %{"position" => 1, "url" => "https://pierwszy.example/", "domain" => "pierwszy.example", "title" => "Pierwszy"},
      %{"position" => 3, "url" => "https://trzeci.example/", "domain" => "trzeci.example", "title" => nil}
    ]

    assessment =
      build(:serp_assessment,
        serp_snapshot: build(:serp_snapshot, results: results),
        labels: [%{"position" => 1, "page_type" => "directory"}, %{"position" => 2, "page_type" => "forum"}]
      )

    assert Competition.first_page(assessment) == [
             %{
               position: 1,
               domain: "pierwszy.example",
               url: "https://pierwszy.example/",
               title: "Pierwszy",
               page_type: :directory,
               page_type_name: "business directory"
             },
             %{
               position: 2,
               domain: "drugi.example",
               url: "https://drugi.example/",
               title: "Drugi",
               page_type: :forum,
               page_type_name: "forum"
             },
             %{
               position: 3,
               domain: "trzeci.example",
               url: "https://trzeci.example/",
               title: nil,
               page_type: nil,
               page_type_name: nil
             }
           ]
  end

  test "every page type has a Polish name for one result" do
    assert SerpAssessment.page_type_names() |> Map.keys() |> Enum.sort() == Enum.sort(SerpAssessment.page_types())
  end

  test "every page type has a Polish plural for the holders summary" do
    assert SerpAssessment.page_type_plurals() |> Map.keys() |> Enum.sort() == Enum.sort(SerpAssessment.page_types())
  end

  test "the checked line says how many of the phrases are checked, in Polish" do
    assert Competition.checked_line(4, 10) == "4 of 10 phrases checked"
    assert Competition.checked_line(0, 3) == "0 of 3 phrases checked"
    assert Competition.checked_line(1, 1) == "1 of 1 phrase checked"
  end

  test "the weak share is the part of the labelled results held by blogs, forums and directories" do
    assert Competition.weak_share(labels(blog: 2, forum: 1, directory: 1, portal: 4, direct_competitor: 2)) == 0.4
    assert Competition.weak_share([]) == nil
  end

  test "the run's assessments come by phrase with their snapshot results" do
    run = insert(:run)
    phrase = insert(:phrase)
    snapshot = insert(:serp_snapshot, phrase: phrase)
    assessment = insert(:serp_assessment, run: run, phrase: phrase, serp_snapshot: snapshot, verdict: :medium)
    insert(:serp_assessment, run: insert(:run), phrase: phrase, serp_snapshot: snapshot)

    assert %{} = assessments = Competition.assessments_for_run(run)
    assert Map.keys(assessments) == [phrase.id]

    assert %SerpAssessment{id: assessment_id, verdict: :medium, serp_snapshot: %SerpSnapshot{results: results}} =
             Map.fetch!(assessments, phrase.id)

    assert assessment_id == assessment.id
    assert results == snapshot.results
  end

  test "the freshest snapshot younger than the maximum age is the one reused" do
    phrase = insert(:phrase)
    now = DateTime.utc_now(:second)
    insert(:serp_snapshot, phrase: phrase, fetched_at: DateTime.shift(now, day: -10))
    freshest = insert(:serp_snapshot, phrase: phrase, fetched_at: DateTime.shift(now, day: -2))
    insert(:serp_snapshot, phrase: phrase, location_code: 9_990_001, fetched_at: now)

    assert %SerpSnapshot{id: freshest_id} = Competition.fresh_snapshot(phrase.id, 2616)
    assert freshest_id == freshest.id
  end

  test "no snapshot is reused once it is older than the maximum age" do
    phrase = insert(:phrase)
    insert(:serp_snapshot, phrase: phrase, fetched_at: DateTime.shift(DateTime.utc_now(:second), day: -31))

    assert Competition.fresh_snapshot(phrase.id, 2616) == nil
  end

  test "the run's assessment summaries give each assessed Phrase's verdict and labels" do
    run = insert(:run)
    labels = labels(direct_competitor: 6, portal: 4)
    assessment = insert(:serp_assessment, run: run, phrase: insert(:phrase), labels: labels, verdict: :strong)
    insert(:serp_assessment, phrase: insert(:phrase))

    assert Competition.assessment_summaries_for_run(run) == %{
             assessment.keyword_id => %{verdict: :strong, labels: labels}
           }
  end

  test "direct competitors in a top 10 are counted" do
    assert Competition.direct_competitor_count(labels(direct_competitor: 3, blog: 7)) == 3
    assert Competition.direct_competitor_count([]) == 0
  end

  test "every Page Type has a plural for who holds the top 10" do
    for page_type <- SerpAssessment.page_types() do
      assert Map.has_key?(SerpAssessment.page_type_plurals(), page_type)
    end
  end

  defp labels(counts_by_page_type) do
    counts_by_page_type
    |> Enum.flat_map(fn {page_type, count} -> List.duplicate(Atom.to_string(page_type), count) end)
    |> Enum.with_index(1)
    |> Enum.map(fn {page_type, position} -> %{"position" => position, "page_type" => page_type} end)
  end
end
