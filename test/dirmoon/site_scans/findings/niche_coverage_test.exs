defmodule Dirmoon.SiteScans.Findings.NicheCoverageTest do
  use ExUnit.Case, async: true

  import Dirmoon.Factory

  alias Dirmoon.SiteScans.Finding
  alias Dirmoon.SiteScans.Findings.NicheCoverage
  alias Dirmoon.SiteScans.ScannedPage

  @home "https://strona-testowa.example/"
  @matched %{"done" => true, "pages" => 2, "matched" => 1}

  test "Niches worth going after with no page are a problem naming each with its monthly searches" do
    niche = summary(%{volume: 320})

    assert [%Finding{question: :niche_coverage, level: :problem, figures: %{niches: [figures], niche_count: 1}}] =
             findings(:niches_without_page, %{matching: @matched, pages: [page(@home)], niches: [niche]})

    assert figures == %{id: niche.niche.id, name: niche.niche.name, volume: 320}
  end

  test "Niches worth going after that have a page are good news, each with its page" do
    with_page = summary()
    without_page = summary()
    service_page = page("https://strona-testowa.example/uslugi", %{cluster_id: with_page.niche.id})

    site = %{matching: @matched, pages: [page(@home), service_page], niches: [with_page, without_page]}

    assert [%Finding{level: :good, pages: [url], figures: %{niches: [%{id: id, pages: [url]}]}}] =
             findings(:niches_with_page, site)

    assert {id, url} == {with_page.niche.id, service_page.url}
  end

  test "Niches not worth going after or rejected are not listed as missing a page" do
    low = summary(%{score: Decimal.new("1")})
    unscored = summary(%{score: nil})
    rejected = summary(%{status: :rejected})

    assert [] =
             findings(:niches_without_page, %{
               matching: @matched,
               pages: [page(@home)],
               niches: [low, unscored, rejected]
             })
  end

  test "two pages matched to one Niche are a warning naming the Niche and both pages" do
    niche = summary()
    first = page("https://strona-testowa.example/a", %{cluster_id: niche.niche.id})
    second = page("https://strona-testowa.example/b", %{cluster_id: niche.niche.id})

    assert [%Finding{level: :warning, figures: %{niches: [%{name: name, pages: pages}]}}] =
             findings(:several_pages_for_one_niche, %{matching: @matched, pages: [first, second], niches: [niche]})

    assert {name, pages} == {niche.niche.name, [first.url, second.url]}
  end

  test "one page per Niche is good news" do
    niche = summary()
    pages = [page("https://strona-testowa.example/a", %{cluster_id: niche.niche.id})]

    assert [%Finding{level: :good}] =
             findings(:several_pages_for_one_niche, %{matching: @matched, pages: pages, niches: [niche]})
  end

  test "with no page matched there is no Finding about pages sharing a Niche" do
    assert [] = findings(:several_pages_for_one_niche, %{matching: @matched, pages: [page(@home)], niches: [summary()]})
  end

  test "a page matched to no Niche and ranking for no Phrase is listed as answering no search" do
    lonely = page("https://strona-testowa.example/galeria")

    assert [%Finding{level: :warning, pages: [url]}] =
             findings(:pages_answering_no_phrase, %{matching: @matched, pages: [page(@home), lonely]})

    assert url == lonely.url
  end

  test "a page that ranks for a Phrase answers a search" do
    ranking = page("https://strona-testowa.example/cennik")
    phrase = build(:run_phrase, current_position: Decimal.new("35"), current_position_url: ranking.url)

    assert [%Finding{level: :good}] =
             findings(:pages_answering_no_phrase, %{
               matching: @matched,
               pages: [page(@home), ranking],
               phrases: [phrase]
             })
  end

  test "a page matched to a Niche answers a search" do
    niche = summary()
    matched = page("https://strona-testowa.example/uslugi", %{cluster_id: niche.niche.id})

    assert [%Finding{level: :good}] =
             findings(:pages_answering_no_phrase, %{matching: @matched, pages: [page(@home), matched], niches: [niche]})
  end

  test "a page whose canonical names another address is a variant, left out of the page lists" do
    niche = summary()
    page_url = "https://strona-testowa.example/uslugi"
    own = page(page_url, %{cluster_id: niche.niche.id})

    variant =
      page("https://strona-testowa.example/uslugi?sort=1", %{
        cluster_id: niche.niche.id,
        facts: %{"word_count" => 300, "canonical" => "https://WWW.strona-testowa.example/uslugi/"}
      })

    site = %{matching: @matched, pages: [page(@home), own, variant], niches: [niche]}

    assert [%Finding{pages: [^page_url]}] = findings(:niches_with_page, site)
    assert [%Finding{level: :good}] = findings(:several_pages_for_one_niche, site)
    assert [%Finding{level: :good}] = findings(:pages_answering_no_phrase, site)
  end

  test "a page whose canonical names itself, in another form, stays a page" do
    niche = summary()

    own =
      page("https://strona-testowa.example/uslugi", %{
        cluster_id: niche.niche.id,
        facts: %{"word_count" => 300, "canonical" => "http://www.strona-testowa.example/uslugi/#oferta"}
      })

    assert [%Finding{pages: ["https://strona-testowa.example/uslugi"]}] =
             findings(:niches_with_page, %{matching: @matched, pages: [page(@home), own], niches: [niche]})
  end

  test "a page asking Google not to list it is not listed as answering no search" do
    hidden = page("https://strona-testowa.example/ukryta", %{facts: %{"word_count" => 300, "noindex" => true}})

    assert [] = findings(:pages_answering_no_phrase, %{matching: @matched, pages: [page(@home), hidden]})
  end

  test "a page ranking under another form of its address answers a search" do
    ranking = page("https://strona-testowa.example/cennik")
    phrase = phrase(Decimal.new("30"), "https://WWW.strona-testowa.example/cennik/")

    site = %{matching: @matched, pages: [page(@home), ranking], phrases: [phrase]}

    assert [%Finding{level: :good}] = findings(:pages_answering_no_phrase, site)
  end

  test "the home page alone gets no Finding about answering no search" do
    assert [] = findings(:pages_answering_no_phrase, %{matching: @matched, pages: [page(@home)]})
  end

  test "before the pages are matched the Niche checks say they are not ready" do
    assert [%Finding{level: :not_checked, figures: %{reason: "not_ready"}}] =
             findings(:niche_matching, %{matching: nil, pages: [page(@home)], niches: [summary()]})

    assert [] = findings(:niches_without_page, %{matching: nil, pages: [page(@home)], niches: [summary()]})
  end

  test "a matching that could not be done says why" do
    matching = %{"done" => false, "reason" => "not_configured"}

    assert [%Finding{level: :not_checked, figures: %{reason: "not_configured"}}] =
             findings(:niche_matching, %{matching: matching, pages: [page(@home)]})
  end

  test "Phrases at positions 11 to 20 are close to the first page, best first, with the page that ranks" do
    in_range = [
      phrase(Decimal.new("20"), "https://strona-testowa.example/b"),
      phrase(Decimal.new("11"), "https://strona-testowa.example/a")
    ]

    outside = [phrase(Decimal.new("10.9"), @home), phrase(Decimal.new("20.1"), @home), phrase(nil, nil)]

    assert [%Finding{level: :warning, figures: %{phrases: [first, second], phrase_count: 2}, pages: pages}] =
             findings(:close_to_first_page, %{matching: nil, phrases: in_range ++ outside})

    assert {first.position, second.position} == {Decimal.new("11"), Decimal.new("20")}
    assert first.phrase == Enum.at(in_range, 1).phrase.phrase
    assert pages == ["https://strona-testowa.example/a", "https://strona-testowa.example/b"]
  end

  test "rejected Phrases are not listed as close to the first page" do
    rejected = %{phrase(Decimal.new("12"), @home) | status: :rejected}

    assert [] = findings(:close_to_first_page, %{matching: nil, phrases: [rejected]})
  end

  test "close to the first page lists at most 20 Phrases and counts them all" do
    phrases = for _number <- 1..25, do: phrase(Decimal.new("15"), @home)

    assert [%Finding{figures: %{phrases: listed, phrase_count: 25}}] =
             findings(:close_to_first_page, %{matching: nil, phrases: phrases})

    assert length(listed) == Finding.max_pages()
  end

  defp findings(check, attributes) do
    %{
      facts: if(attributes.matching, do: %{"matching" => attributes.matching}, else: %{}),
      pages: Map.get(attributes, :pages, []),
      home_page: @home,
      niches: Map.get(attributes, :niches, []),
      phrases: Map.get(attributes, :phrases, []),
      page_limit: 50
    }
    |> NicheCoverage.check()
    |> Enum.filter(&(&1.check == check))
  end

  defp summary(attributes \\ %{}) do
    niche =
      build(:niche,
        id: ExMachina.sequence(:findings_niche_id, & &1),
        score: Map.get(attributes, :score, Decimal.new("6")),
        status: Map.get(attributes, :status, :proposed)
      )

    %{niche: niche, volume: Map.get(attributes, :volume, 100), cpc: nil, competition: nil}
  end

  defp phrase(position, url), do: build(:run_phrase, current_position: position, current_position_url: url)

  defp page(url, attributes \\ %{}) do
    struct(%ScannedPage{url: url, http_status: 200, facts: %{"word_count" => 300, "final_url" => url}}, attributes)
  end
end
