defmodule Dirmoon.SiteScans.FindingsTest do
  use ExUnit.Case, async: true

  import Dirmoon.Factory

  alias Dirmoon.SiteScans.Finding
  alias Dirmoon.SiteScans.Findings
  alias Dirmoon.SiteScans.ScannedPage
  alias Dirmoon.SiteScans.SiteScan

  @home "https://strona-testowa.example/"

  test "Findings come ordered by question, then problems, warnings, not checked and good news" do
    facts = %{
      "home_page" => @home,
      "https" => true,
      "www_and_bare_both_answer" => true,
      "robots_txt" => %{"present" => true, "status" => 200, "unreadable" => false, "blocks_site" => true},
      "indexed_pages" => %{"checked" => false, "reason" => "failed"},
      "speed" => %{"checked" => false, "reason" => "quota"},
      "business_profile" => %{"checked" => false, "reason" => "no_business_name"}
    }

    findings = build_findings(scan(facts, [page(@home, %{"title" => nil})]))

    assert Enum.map(findings, & &1.question) == Enum.sort_by(Enum.map(findings, & &1.question), &question_index/1)

    assert [
             %Finding{check: :robots_txt, level: :problem},
             %Finding{check: :www_and_bare, level: :warning},
             %Finding{check: :indexed_pages, level: :not_checked},
             %Finding{check: :https, level: :good} | _rest
           ] = findings

    assert %Finding{question: :page_content, level: :problem, check: :missing_title} =
             Enum.find(findings, &(&1.question == :page_content))
  end

  test "a scan that has stored nothing yet gives only the Phrases close to the first page and the matching not ready" do
    assert [%Finding{check: :close_to_first_page}, %Finding{check: :niche_matching, level: :not_checked}] =
             build_findings(scan(%{}, []))
  end

  test "Findings are built whatever subset of the site facts is stored" do
    full = full_site_facts()
    keys = Map.keys(full)
    pages = [page(@home), page("https://strona-testowa.example/uslugi")]

    for size <- 0..length(keys), dropped <- combinations(keys, size) do
      assert is_list(build_findings(scan(Map.drop(full, dropped), pages)))
    end
  end

  test "Findings are built whatever subset of a page's facts is stored" do
    :rand.seed(:exsss, {11, 22, 33})
    keys = Map.keys(full_page_facts(@home))

    for _try <- 1..300 do
      dropped = Enum.filter(keys, fn _key -> :rand.uniform(2) == 1 end)
      pages = [%ScannedPage{url: @home, http_status: 200, facts: Map.drop(full_page_facts(@home), dropped)}]

      assert is_list(build_findings(scan(full_site_facts(), pages)))
    end
  end

  test "Findings are built whatever type each site fact holds" do
    full = full_site_facts()
    pages = [page(@home), page("https://strona-testowa.example/uslugi")]

    for key <- Map.keys(full), value <- wrong_types() do
      assert is_list(build_findings(scan(Map.put(full, key, value), pages)))
    end

    for key <- Map.keys(full), value <- wrong_types(), is_map(full[key]), inner <- Map.keys(full[key]) do
      assert is_list(build_findings(scan(Map.put(full, key, Map.put(full[key], inner, value)), pages)))
    end
  end

  test "Findings are built whatever type each page fact holds" do
    full = full_page_facts(@home)

    for key <- Map.keys(full), value <- wrong_types() do
      pages = [%ScannedPage{url: @home, http_status: 200, facts: Map.put(full, key, value)}]
      assert is_list(build_findings(scan(full_site_facts(), pages)))
    end

    for value <- wrong_types(), inner <- Map.keys(full["ways_to_act"]) do
      pages = [%ScannedPage{url: @home, http_status: 200, facts: put_in(full, ["ways_to_act", inner], value)}]
      assert is_list(build_findings(scan(full_site_facts(), pages)))
    end
  end

  test "every Finding built is one of the checks and levels the rules list" do
    listed = MapSet.new(Findings.checks())
    pages = [page(@home), page("https://strona-testowa.example/uslugi", %{"noindex" => true, "title" => nil})]

    for finding <- build_findings(scan(full_site_facts(), pages)) do
      assert MapSet.member?(listed, Map.take(finding, [:question, :check, :level]))
    end
  end

  defp wrong_types, do: [nil, "tekst", 7, 0.5, true, ["tekst", 7, nil], %{"klucz" => "tekst"}, [%{"klucz" => 1}]]

  defp build_findings(scan) do
    niche = build(:niche, id: ExMachina.sequence(:findings_niche_id, & &1), score: Decimal.new("6"))
    phrase = build(:run_phrase, current_position: Decimal.new("14"), current_position_url: @home)

    Findings.build(%{
      scan: scan,
      niches: [%{niche: niche, volume: 90, cpc: nil, competition: nil}],
      phrases: [phrase],
      page_limit: 50
    })
  end

  defp question_index(question), do: Enum.find_index(Finding.questions(), &(&1 == question))

  defp combinations(_keys, 0), do: [[]]
  defp combinations([], _size), do: []

  defp combinations([key | rest], size),
    do: Enum.map(combinations(rest, size - 1), &[key | &1]) ++ combinations(rest, size)

  defp scan(facts, pages), do: %SiteScan{status: :scanning, facts: facts, scanned_pages: pages}

  defp page(url, facts \\ %{}),
    do: %ScannedPage{url: url, http_status: 200, facts: Map.merge(full_page_facts(url), facts)}

  defp full_site_facts do
    %{
      "home_page" => @home,
      "addresses" => [%{"url" => @home, "status" => 200, "final_url" => @home, "redirects" => [], "error" => nil}],
      "https" => true,
      "www_and_bare_both_answer" => true,
      "robots_txt" => %{
        "present" => true,
        "status" => 200,
        "unreadable" => false,
        "blocks_site" => false,
        "sitemaps" => []
      },
      "sitemap" => %{"found" => true, "url" => @home <> "sitemap.xml", "page_count" => 2, "pages" => []},
      "blocked_pages" => [@home <> "admin"],
      "links_checked" => 1,
      "broken_links" => [%{"url" => @home <> "stara", "status" => 404, "linked_from" => [@home]}],
      "speed" => %{
        "checked" => true,
        "performance_score" => 70,
        "largest_contentful_paint_ms" => 3_000,
        "cumulative_layout_shift" => 0.05,
        "field" => %{"interaction_to_next_paint" => %{"percentile" => 150, "scope" => "origin"}},
        "phone_checks" => [%{"id" => "meta-viewport", "passed" => true}]
      },
      "indexed_pages" => %{"checked" => true, "count" => 4},
      "business_profile" => %{"checked" => true, "name" => "Firma testowa", "found" => true, "links_to_site" => true},
      "matching" => %{"done" => true, "pages" => 2, "matched" => 1}
    }
  end

  defp full_page_facts(url) do
    %{
      "title" => "Strona testowa #{url}",
      "description" => "Opis strony testowej",
      "canonical" => url,
      "robots" => nil,
      "language" => "pl",
      "noindex" => false,
      "viewport" => true,
      "password_field" => false,
      "main_headings" => ["Nagłówek"],
      "sub_headings" => [],
      "word_count" => 300,
      "text_fingerprint" => "odcisk",
      "images" => 2,
      "images_without_description" => 1,
      "internal_links" => [],
      "external_links" => [],
      "structured_data_types" => ["LocalBusiness"],
      "business_name" => "Firma testowa",
      "phones" => ["+48500000001"],
      "emails" => [],
      "ways_to_act" => %{"phone_links" => 1, "email_links" => 0, "forms" => 0, "button_links" => 0},
      "final_url" => url,
      "redirects" => [],
      "content_type" => "text/html"
    }
  end
end
