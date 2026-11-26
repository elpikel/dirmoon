defmodule Dirmoon.SiteScans.Findings.VisitorTest do
  use ExUnit.Case, async: true

  alias Dirmoon.SiteScans.Finding
  alias Dirmoon.SiteScans.Findings.Visitor
  alias Dirmoon.SiteScans.ScannedPage

  @home "https://strona-testowa.example/"

  test "a performance score of 90 or more is good news" do
    assert [%Finding{question: :visitor, level: :good, figures: %{score: 90}}] =
             findings(:performance_score, speed(%{"performance_score" => 90}))
  end

  test "a performance score from 50 to 89 is a warning" do
    assert [%Finding{level: :warning, figures: %{score: 50}}] =
             findings(:performance_score, speed(%{"performance_score" => 50}))
  end

  test "a performance score under 50 is a problem" do
    assert [%Finding{level: :problem, figures: %{score: 49}}] =
             findings(:performance_score, speed(%{"performance_score" => 49}))
  end

  test "a missing performance score gives no Finding" do
    assert [] = findings(:performance_score, speed(%{"performance_score" => nil}))
  end

  test "the main content showing within 2.5 s for real visitors is good news from their figure" do
    field = %{"largest_contentful_paint" => %{"percentile" => 2_500, "category" => "FAST", "scope" => "page"}}

    assert [%Finding{level: :good, figures: %{milliseconds: 2_500, source: "page"}}] =
             findings(:largest_contentful_paint, speed(%{"field" => field, "largest_contentful_paint_ms" => 9_000}))
  end

  test "the main content showing within 4 s in Google's test load is a warning from the lab figure" do
    assert [%Finding{level: :warning, figures: %{milliseconds: 4_000, source: "lab"}}] =
             findings(:largest_contentful_paint, speed(%{"largest_contentful_paint_ms" => 4_000}))
  end

  test "the main content showing after 4 s is a problem" do
    assert [%Finding{level: :problem}] =
             findings(:largest_contentful_paint, speed(%{"largest_contentful_paint_ms" => 4_001}))
  end

  test "no loading figure gives no Finding about the main content" do
    assert [] = findings(:largest_contentful_paint, speed(%{}))
  end

  test "answering a tap within 200 ms for real visitors is good news" do
    field = %{"interaction_to_next_paint" => %{"percentile" => 200, "scope" => "origin"}}

    assert [%Finding{level: :good, figures: %{milliseconds: 200, source: "origin"}}] =
             findings(:interaction_to_next_paint, speed(%{"field" => field}))
  end

  test "answering a tap within 500 ms is a warning" do
    field = %{"interaction_to_next_paint" => %{"percentile" => 500, "scope" => "page"}}

    assert [%Finding{level: :warning}] = findings(:interaction_to_next_paint, speed(%{"field" => field}))
  end

  test "answering a tap after 500 ms is a problem" do
    field = %{"interaction_to_next_paint" => %{"percentile" => 501, "scope" => "page"}}

    assert [%Finding{level: :problem}] = findings(:interaction_to_next_paint, speed(%{"field" => field}))
  end

  test "without real visitors' figures there is no Finding about answering a tap" do
    assert [] = findings(:interaction_to_next_paint, speed(%{"field" => nil}))
  end

  test "a page that barely jumps for real visitors is good news, their figure read as Google scales it" do
    field = %{"cumulative_layout_shift" => %{"percentile" => 10, "scope" => "page"}}

    assert [%Finding{level: :good, figures: %{value: 0.1, source: "page"}}] =
             findings(:cumulative_layout_shift, speed(%{"field" => field, "cumulative_layout_shift" => 0.9}))
  end

  test "a page jumping up to 0.25 in Google's test load is a warning" do
    assert [%Finding{level: :warning, figures: %{value: 0.25, source: "lab"}}] =
             findings(:cumulative_layout_shift, speed(%{"cumulative_layout_shift" => 0.25}))
  end

  test "a page jumping more than 0.25 is a problem" do
    assert [%Finding{level: :problem}] = findings(:cumulative_layout_shift, speed(%{"cumulative_layout_shift" => 0.3}))
  end

  test "no layout figure gives no Finding about the page jumping" do
    assert [] = findings(:cumulative_layout_shift, speed(%{}))
  end

  test "each failed phone check is its own warning and the passed ones are good news together" do
    checks = [
      %{"id" => "meta-viewport", "passed" => false},
      %{"id" => "target-size", "passed" => false},
      %{"id" => "viewport-insight", "passed" => true},
      %{"id" => "other", "passed" => nil}
    ]

    assert [
             %Finding{level: :warning, figures: %{check_id: "meta-viewport"}},
             %Finding{level: :warning, figures: %{check_id: "target-size"}},
             %Finding{level: :good, figures: %{check_ids: ["viewport-insight"]}}
           ] = findings(:phone_usability, speed(%{"phone_checks" => checks}))
  end

  test "no phone check gives no phone usability Finding" do
    assert [] = findings(:phone_usability, speed(%{"phone_checks" => nil}))
  end

  test "speed not checked says why" do
    facts = %{"speed" => %{"checked" => false, "reason" => "not_configured"}}

    assert [%Finding{level: :not_checked, figures: %{reason: "not_configured"}}] = findings(:speed, site(facts))
  end

  test "a page not set up for phones is a warning listing it" do
    other = page("https://strona-testowa.example/stara", %{"viewport" => false})

    assert [%Finding{level: :warning, pages: [url]}] = findings(:viewport, site(%{}, [page(@home), other]))
    assert url == other.url
  end

  test "every page set up for phones is good news" do
    assert [%Finding{level: :good}] = findings(:viewport, site(%{}, [page(@home)]))
  end

  test "a page with no next step for the visitor is a warning listing it" do
    dead_end = page("https://strona-testowa.example/blog", %{"ways_to_act" => ways_to_act(%{})})

    assert [%Finding{level: :warning, pages: [url]}] = findings(:ways_to_act, site(%{}, [page(@home), dead_end]))
    assert url == dead_end.url
  end

  test "every page offering a next step is good news" do
    assert [%Finding{level: :good}] = findings(:ways_to_act, site(%{}, [page(@home)]))
  end

  test "a page whose ways to act were not read is not listed as a dead end" do
    assert [%Finding{level: :good}] = findings(:ways_to_act, site(%{}, [page(@home, %{"ways_to_act" => nil})]))
  end

  test "a scan that stored nothing yet has no visitor Finding" do
    assert [] = Visitor.check(site(%{}))
  end

  defp findings(check, site), do: site |> Visitor.check() |> Enum.filter(&(&1.check == check))

  defp speed(result), do: site(%{"speed" => Map.put(result, "checked", true)})

  defp site(facts, pages \\ []),
    do: %{facts: facts, pages: pages, home_page: @home, niches: [], phrases: [], page_limit: 50}

  defp ways_to_act(counts),
    do: Map.merge(%{"phone_links" => 0, "email_links" => 0, "forms" => 0, "button_links" => 0}, counts)

  defp page(url, facts \\ %{}) do
    good_facts = %{"word_count" => 300, "viewport" => true, "ways_to_act" => ways_to_act(%{"forms" => 1})}
    %ScannedPage{url: url, http_status: 200, facts: Map.merge(good_facts, facts)}
  end
end
