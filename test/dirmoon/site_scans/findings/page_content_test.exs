defmodule Dirmoon.SiteScans.Findings.PageContentTest do
  use ExUnit.Case, async: true

  alias Dirmoon.SiteScans.Finding
  alias Dirmoon.SiteScans.Findings.PageContent
  alias Dirmoon.SiteScans.ScannedPage

  @home "https://strona-testowa.example/"
  @other "https://strona-testowa.example/uslugi"

  test "a page without a title is a problem listing it" do
    assert [%Finding{question: :page_content, level: :problem, pages: [@other]}] =
             findings(:missing_title, [page(@home), page(@other, %{"title" => nil})])
  end

  test "a blank title counts as missing" do
    assert [%Finding{level: :problem, pages: [@other]}] =
             findings(:missing_title, [page(@home), page(@other, %{"title" => "  "})])
  end

  test "every page having a title is good news" do
    assert [%Finding{level: :good}] = findings(:missing_title, [page(@home)])
  end

  test "a title shared by two pages is a warning naming the title and both pages" do
    pages = [page(@home, %{"title" => "Usługi testowe"}), page(@other, %{"title" => "Usługi testowe "})]

    assert [
             %Finding{
               level: :warning,
               pages: [@home, @other],
               figures: %{titles: [%{title: "Usługi testowe", pages: [@home, @other]}]}
             }
           ] = findings(:duplicate_titles, pages)
  end

  test "titles all different are good news" do
    assert [%Finding{level: :good}] = findings(:duplicate_titles, [page(@home), page(@other)])
  end

  test "a title over 60 characters is a warning with its length" do
    long = String.duplicate("a", 61)

    assert [%Finding{level: :warning, pages: [@other], figures: %{lengths: [%{url: @other, length: 61}]}}] =
             findings(:long_titles, [page(@home), page(@other, %{"title" => long})])
  end

  test "titles within 60 characters are good news" do
    assert [%Finding{level: :good}] = findings(:long_titles, [page(@home, %{"title" => String.duplicate("a", 60)})])
  end

  test "a title under 10 characters is a warning with its length" do
    assert [%Finding{level: :warning, figures: %{lengths: [%{url: @other, length: 5}]}}] =
             findings(:short_titles, [page(@home), page(@other, %{"title" => "Start"})])
  end

  test "titles of 10 characters or more are good news" do
    assert [%Finding{level: :good}] = findings(:short_titles, [page(@home, %{"title" => String.duplicate("a", 10)})])
  end

  test "a page without a description is a warning listing it" do
    assert [%Finding{level: :warning, pages: [@other]}] =
             findings(:missing_description, [page(@home), page(@other, %{"description" => nil})])
  end

  test "every page having a description is good news" do
    assert [%Finding{level: :good}] = findings(:missing_description, [page(@home)])
  end

  test "a description shared by two pages is a warning naming it and both pages" do
    pages = [page(@home, %{"description" => "Opis testowy"}), page(@other, %{"description" => "Opis testowy"})]

    assert [%Finding{level: :warning, figures: %{descriptions: [%{description: "Opis testowy", pages: [@home, @other]}]}}] =
             findings(:duplicate_descriptions, pages)
  end

  test "descriptions all different are good news" do
    assert [%Finding{level: :good}] = findings(:duplicate_descriptions, [page(@home), page(@other)])
  end

  test "a description over 160 characters is a warning with its length" do
    long = String.duplicate("o", 161)

    assert [%Finding{level: :warning, figures: %{lengths: [%{url: @other, length: 161}]}}] =
             findings(:long_descriptions, [page(@home), page(@other, %{"description" => long})])
  end

  test "descriptions within 160 characters are good news" do
    assert [%Finding{level: :good}] = findings(:long_descriptions, [page(@home)])
  end

  test "a page without a main heading is a warning listing it" do
    assert [%Finding{level: :warning, pages: [@other]}] =
             findings(:missing_main_heading, [page(@home), page(@other, %{"main_headings" => []})])
  end

  test "every page having a main heading is good news" do
    assert [%Finding{level: :good}] = findings(:missing_main_heading, [page(@home)])
  end

  test "a page with several main headings is a warning with their count" do
    assert [%Finding{level: :warning, figures: %{counts: [%{url: @other, count: 2}]}}] =
             findings(:several_main_headings, [page(@home), page(@other, %{"main_headings" => ["Jeden", "Dwa"]})])
  end

  test "one main heading per page is good news" do
    assert [%Finding{level: :good}] = findings(:several_main_headings, [page(@home)])
  end

  test "a page with very little text is a warning with its word count" do
    assert [%Finding{level: :warning, figures: %{word_counts: [%{url: @other, word_count: 40}]}}] =
             findings(:little_text, [page(@home), page(@other, %{"word_count" => 40})])
  end

  test "pages with enough text are good news" do
    assert [%Finding{level: :good}] = findings(:little_text, [page(@home)])
  end

  test "a page in a language written without spaces is not judged by its word count" do
    japanese = page(@other, %{"word_count" => 3, "language" => "ja-JP"})

    assert [%Finding{level: :good}] = findings(:little_text, [page(@home), japanese])
  end

  test "a page that declares no language is judged by its word count" do
    assert [%Finding{level: :warning, pages: [@other]}] =
             findings(:little_text, [page(@home), page(@other, %{"word_count" => 40, "language" => nil})])
  end

  test "a site written only in languages without spaces gets no little text Finding" do
    assert [] = findings(:little_text, [page(@home, %{"word_count" => 3, "language" => "zh"})])
  end

  test "two pages with the same text are a warning listing them together" do
    pages = [page(@home, %{"text_fingerprint" => "odcisk"}), page(@other, %{"text_fingerprint" => "odcisk"})]

    assert [%Finding{level: :warning, pages: [@home, @other], figures: %{shared_texts: [%{pages: [@home, @other]}]}}] =
             findings(:duplicate_text, pages)
  end

  test "pages with different or no text are good news" do
    assert [%Finding{level: :good}] =
             findings(:duplicate_text, [
               page(@home, %{"text_fingerprint" => nil}),
               page(@other, %{"text_fingerprint" => nil})
             ])
  end

  test "images without descriptions are a warning with the counts" do
    pages = [
      page(@home, %{"images" => 4, "images_without_description" => 1}),
      page(@other, %{"images" => 3, "images_without_description" => 3})
    ]

    assert [%Finding{level: :warning, pages: [@home, @other], figures: %{images: 7, without_description: 4}}] =
             findings(:images_without_description, pages)
  end

  test "every image described is good news" do
    assert [%Finding{level: :good}] = findings(:images_without_description, [page(@home, %{"images" => 2})])
  end

  test "noindex pages are left out of the content checks" do
    hidden = page(@other, %{"noindex" => true, "title" => nil})

    assert [%Finding{level: :good}] = findings(:missing_title, [page(@home), hidden])
  end

  test "pages that are not the site's own readable pages are left out of the content checks" do
    pages = [
      page(@home),
      page(@other, %{"title" => nil}, %{http_status: 404}),
      page("https://strona-testowa.example/poza", %{"off_site" => true, "title" => nil}),
      %ScannedPage{url: "https://strona-testowa.example/plik.pdf", http_status: 200, facts: %{"final_url" => "x"}}
    ]

    assert [%Finding{level: :good}] = findings(:missing_title, pages)
  end

  test "a site with no readable page has no content Finding" do
    assert [] = PageContent.check(site([]))
  end

  test "a Finding lists at most 20 pages and counts them all" do
    pages = for number <- 1..25, do: page("https://strona-testowa.example/strona-#{number}", %{"title" => nil})

    assert [%Finding{pages: listed, page_count: 25}] = findings(:missing_title, pages)
    assert length(listed) == Finding.max_pages()
  end

  test "a page whose canonical names another address is a variant, left out of the content checks" do
    variant =
      page("https://strona-testowa.example/uslugi?strona=2", %{
        "title" => nil,
        "canonical" => @other,
        "text_fingerprint" => "odcisk #{@other}"
      })

    pages = [page(@home), page(@other), variant]

    assert [%Finding{level: :good}] = findings(:missing_title, pages)
    assert [%Finding{level: :good}] = findings(:duplicate_text, pages)
  end

  defp findings(check, pages), do: pages |> site() |> PageContent.check() |> Enum.filter(&(&1.check == check))

  defp site(pages), do: %{facts: %{}, pages: pages, home_page: @home, niches: [], phrases: [], page_limit: 50}

  defp page(url, facts \\ %{}, attributes \\ %{}) do
    good_facts = %{
      "title" => "Strona testowa #{url}",
      "description" => "Opis strony testowej #{url}",
      "main_headings" => ["Nagłówek #{url}"],
      "word_count" => 400,
      "text_fingerprint" => "odcisk #{url}",
      "images" => 0,
      "images_without_description" => 0,
      "language" => "pl",
      "noindex" => false,
      "final_url" => url
    }

    struct(%ScannedPage{url: url, http_status: 200, facts: Map.merge(good_facts, facts)}, attributes)
  end
end
