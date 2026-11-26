defmodule Dirmoon.SiteScans.Findings.BusinessTest do
  use ExUnit.Case, async: true

  alias Dirmoon.SiteScans.Finding
  alias Dirmoon.SiteScans.Findings.Business
  alias Dirmoon.SiteScans.ScannedPage

  @home "https://strona-testowa.example/"
  @other "https://strona-testowa.example/kontakt"

  test "no page with a phone or e-mail link a visitor can tap is a warning" do
    assert [%Finding{question: :business, level: :warning, figures: figures}] =
             findings(:tappable_contact, [page(@home), page(@other)])

    assert figures == %{phone_count: 0, email_count: 0}
  end

  test "an e-mail link on one page is a way to get in touch with a tap" do
    assert [%Finding{level: :good, figures: %{email_count: 1}}] =
             findings(:tappable_contact, [page(@home), page(@other, %{"emails" => ["biuro@strona-testowa.example"]})])
  end

  test "a phone link on one page is a way to get in touch with a tap" do
    assert [%Finding{level: :good, figures: %{phone_count: 1}}] =
             findings(:tappable_contact, [page(@home, %{"phones" => ["+48500000001"]})])
  end

  test "no address in any page's structured data is a warning" do
    assert [%Finding{level: :warning}] =
             findings(:address_in_structured_data, [page(@home, %{"structured_data_types" => ["Organization"]})])
  end

  test "an address type in the structured data is good news" do
    for type <- ["PostalAddress", "LocalBusiness", "Place"] do
      assert [%Finding{level: :good}] =
               findings(:address_in_structured_data, [page(@home, %{"structured_data_types" => [type]})])
    end
  end

  test "a number written with and without its country code counts once" do
    pages = [page(@home, %{"phones" => ["+48 600 000 000"]}), page(@other, %{"phones" => ["600000000"]})]

    assert [%Finding{level: :good, figures: %{phones: ["+48 600 000 000"], phone_count: 1}}] =
             findings(:phone_numbers, pages)
  end

  test "two different phone numbers across pages are a warning listing them" do
    pages = [page(@home, %{"phones" => ["+48500000001"]}), page(@other, %{"phones" => ["+48500000002", "+48500000001"]})]

    assert [%Finding{level: :warning, figures: %{phones: ["+48500000001", "+48500000002"], phone_count: 2}}] =
             findings(:phone_numbers, pages)
  end

  test "the phone numbers listed stop at five" do
    phones = for number <- 1..7, do: "+4850000000#{number}"

    assert [%Finding{figures: %{phones: listed, phone_count: 7}}] =
             findings(:phone_numbers, [page(@home, %{"phones" => phones})])

    assert Enum.count(listed) == 5
  end

  test "one phone number on every page is good news" do
    pages = [page(@home, %{"phones" => ["+48500000001"]}), page(@other, %{"phones" => ["+48500000001"]})]

    assert [%Finding{level: :good, figures: %{phone_count: 1}}] = findings(:phone_numbers, pages)
  end

  test "no phone number gives no Finding about several numbers" do
    assert [] = findings(:phone_numbers, [page(@home)])
  end

  test "a phone link with no digit in it is no phone number, for the count or for tapping" do
    pages = [page(@home, %{"phones" => ["", "abc", "+48500000001"]}), page(@other, %{"phones" => ["zadzwoń"]})]

    assert [%Finding{level: :good, figures: %{phones: ["+48500000001"], phone_count: 1}}] =
             findings(:phone_numbers, pages)

    assert [%Finding{level: :warning, figures: %{phone_count: 0}}] =
             findings(:tappable_contact, [page(@home, %{"phones" => ["", "abc"]})])

    assert [] = findings(:phone_numbers, [page(@home, %{"phones" => ["", "abc"]})])
  end

  test "no structured data on any page is a warning" do
    assert [%Finding{level: :warning}] = findings(:structured_data, [page(@home)])
  end

  test "structured data is good news with its types" do
    pages = [
      page(@home, %{"structured_data_types" => ["Organization"]}),
      page(@other, %{"structured_data_types" => ["FAQPage"]})
    ]

    assert [%Finding{level: :good, figures: %{types: ["Organization", "FAQPage"]}}] = findings(:structured_data, pages)
  end

  test "a page without a declared language is a warning listing it" do
    assert [%Finding{level: :warning, pages: [@other]}] =
             findings(:language_declared, [page(@home), page(@other, %{"language" => nil})])
  end

  test "every page declaring its language is good news" do
    assert [%Finding{level: :good}] = findings(:language_declared, [page(@home)])
  end

  test "the languages the pages declare are given as figures" do
    assert [%Finding{level: :good, figures: %{languages: ["pl", "en"]}}] =
             findings(:declared_languages, [page(@home), page(@other, %{"language" => "en"})])
  end

  test "no declared language gives no Finding listing languages" do
    assert [] = findings(:declared_languages, [page(@home, %{"language" => " "})])
  end

  test "a Business Profile found and linking to the site is good news" do
    profile = profile(%{"found" => true, "links_to_site" => true, "rating" => 4.6, "votes" => 31})

    assert [%Finding{level: :good, figures: %{name: "Firma testowa", rating: 4.6, votes: 31, links_to_site: true}}] =
             profile_findings(profile)
  end

  test "a Business Profile found but not linking to the site is a warning" do
    assert [%Finding{level: :warning, figures: %{found: true, links_to_site: false}}] =
             profile_findings(profile(%{"found" => true, "links_to_site" => false}))
  end

  test "no Business Profile found is a warning" do
    assert [%Finding{level: :warning, figures: %{found: false}}] =
             profile_findings(profile(%{"found" => false, "links_to_site" => false}))
  end

  test "a Business Profile not looked up because the site names no business says so" do
    assert [%Finding{level: :not_checked, figures: %{reason: "no_business_name"}}] =
             profile_findings(%{"checked" => false, "reason" => "no_business_name"})
  end

  test "other sites linking to the site is good news with their number" do
    assert [%Finding{question: :business, level: :good, figures: %{count: 17}}] =
             linking_sites_findings(%{"checked" => true, "count" => 17})
  end

  test "no other site linking to the site is a warning" do
    assert [%Finding{level: :warning, figures: %{count: 0}}] =
             linking_sites_findings(%{"checked" => true, "count" => 0})
  end

  test "a count the link index has no data for is not checked, for want of data, never zero" do
    assert [%Finding{level: :not_checked, figures: %{reason: "no_data"}}] =
             linking_sites_findings(%{"checked" => true, "count" => nil})
  end

  test "linking sites not looked up are not checked, with the reason" do
    assert [%Finding{level: :not_checked, figures: %{reason: "unavailable"}}] =
             linking_sites_findings(%{"checked" => false, "reason" => "unavailable"})
  end

  test "a scan without the linking sites fact gives no Finding about them" do
    assert linking_sites_findings(nil) == []
  end

  test "a site with no readable page gives only the Business Profile Finding" do
    site = %{
      facts: %{"business_profile" => profile(%{"found" => false})},
      pages: [],
      home_page: @home,
      niches: [],
      phrases: [],
      page_limit: 50
    }

    assert [%Finding{check: :business_profile}] = Business.check(site)
  end

  defp findings(check, pages) do
    %{facts: %{}, pages: pages, home_page: @home, niches: [], phrases: [], page_limit: 50}
    |> Business.check()
    |> Enum.filter(&(&1.check == check))
  end

  defp profile_findings(profile) do
    %{facts: %{"business_profile" => profile}, pages: [], home_page: @home, niches: [], phrases: [], page_limit: 50}
    |> Business.check()
    |> Enum.filter(&(&1.check == :business_profile))
  end

  defp linking_sites_findings(fact) do
    %{facts: %{"linking_sites" => fact}, pages: [], home_page: @home, niches: [], phrases: [], page_limit: 50}
    |> Business.check()
    |> Enum.filter(&(&1.check == :linking_sites))
  end

  defp profile(attributes),
    do:
      Map.merge(
        %{"checked" => true, "name" => "Firma testowa", "title" => "Firma testowa", "claimed" => true},
        attributes
      )

  defp page(url, facts \\ %{}) do
    good_facts = %{"word_count" => 300, "language" => "pl", "phones" => [], "emails" => [], "structured_data_types" => []}
    %ScannedPage{url: url, http_status: 200, facts: Map.merge(good_facts, facts)}
  end
end
