defmodule Dirmoon.SiteScans.Findings.Business do
  @moduledoc """
  Findings for the question "does the site show a real business?"
  (`:business`), from the readable pages
  (`Dirmoon.SiteScans.Findings.SitePages.readable/1`; with none, only the
  Business Profile can give a Finding):

    * `:tappable_contact`: no page has a phone (`tel:`) or e-mail
      (`mailto:`) link a visitor can tap (warning), else good (figures
      `phone_count`, `email_count`). Phone numbers and addresses written as
      plain text are not looked for: their formats differ from country to
      country, so the check says only what it measures
    * `:address_in_structured_data`: no address type (`PostalAddress`,
      `LocalBusiness`, `Place`) in any page's structured data (warning),
      else good
    * `:phone_numbers`: more than one phone number in the pages' phone links
      (warning: several can be right, so the figures list them for the owner
      to judge), one is good; a number written with and without its country
      code counts once (the same last 9 digits), and a phone link with no
      digit in it is no number and is left out (here and in
      `:tappable_contact`); figures `phones` (at most 5) and `phone_count`
    * `:structured_data`: no structured data on any page (warning), else
      good with its `types` (at most 20)
    * `:language_declared`: pages that don't declare their language
      (warning), else good
    * `:declared_languages`: the languages the pages declare, as figures
      only (good; figures `languages`), when any page declares one

  From the scan's `"business_profile"` fact, `:business_profile`: found and
  linking to the site (good), found but linking elsewhere or nowhere
  (warning), not found (warning); figures `name` (the name looked up),
  `title`, `rating`, `votes`, `claimed`. Not checked with its `reason`;
  `"no_business_name"` means the site's structured data names no business.

  From the scan's `"linking_sites"` fact, `:linking_sites`: how many other
  sites link to the site, as DataForSEO's link index knows (figures
  `count`). Some is good and none is a warning: whether a number is few or
  many needs a comparison (the Niche's competitors on the results screen),
  so there is no threshold. A count the index has no data for is not
  checked with the reason `"no_data"`; a lookup not made is not checked
  with its `reason`.
  """

  alias Dirmoon.SiteScans.Finding
  alias Dirmoon.SiteScans.Findings.SitePages

  @question :business
  @checks [
    tappable_contact: [:warning, :good],
    address_in_structured_data: [:warning, :good],
    phone_numbers: [:warning, :good],
    structured_data: [:warning, :good],
    language_declared: [:warning, :good],
    declared_languages: [:good],
    business_profile: [:warning, :not_checked, :good],
    linking_sites: [:warning, :not_checked, :good]
  ]
  @check_levels for {check, levels} <- @checks, level <- levels, do: {check, level}
  @max_phones 5
  @max_types 20
  @address_types ~w(PostalAddress LocalBusiness Place)
  @national_digits 9
  @no_data "no_data"

  @doc "Every check this rule makes, with each level it can give: `[%{question:, check:, level:}]`."
  def checks, do: for({check, level} <- @check_levels, do: %{question: @question, check: check, level: level})

  @doc "The `:business` Findings of the site (`Dirmoon.SiteScans.Findings`)."
  def check(%{facts: facts, pages: pages}) do
    readable = SitePages.readable(pages)

    List.flatten([
      page_findings(readable),
      business_profile(facts["business_profile"]),
      linking_sites(facts["linking_sites"])
    ])
  end

  defp page_findings([]), do: []

  defp page_findings(readable) do
    phones = readable |> all_of("phones") |> distinct_phones()
    types = all_of(readable, "structured_data_types")

    [
      tappable_contact(%{phones: phones, emails: all_of(readable, "emails")}),
      address_in_structured_data(types),
      phone_numbers(phones),
      structured_data(types),
      language_declared(readable),
      declared_languages(readable)
    ]
  end

  defp all_of(readable, key) do
    readable
    |> Enum.flat_map(&List.wrap(&1.facts[key]))
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp distinct_phones(phones) do
    phones
    |> Enum.filter(&String.match?(&1, ~r/\d/))
    |> Enum.reduce([], fn phone, kept ->
      if Enum.any?(kept, &same_phone?(&1, phone)), do: kept, else: [phone | kept]
    end)
    |> Enum.reverse()
  end

  defp same_phone?(phone, other) do
    digits = String.replace(phone, ~r/\D/, "")
    other_digits = String.replace(other, ~r/\D/, "")

    String.ends_with?(digits, String.slice(other_digits, -@national_digits, @national_digits)) or
      String.ends_with?(other_digits, String.slice(digits, -@national_digits, @national_digits))
  end

  defp tappable_contact(%{phones: phones, emails: emails}) do
    figures = %{phone_count: length(phones), email_count: length(emails)}
    level = if phones == [] and emails == [], do: :warning, else: :good
    finding(:tappable_contact, level, %{figures: figures})
  end

  defp address_in_structured_data(types) do
    level = if Enum.any?(types, &(&1 in @address_types)), do: :good, else: :warning
    finding(:address_in_structured_data, level)
  end

  defp phone_numbers([]), do: []

  defp phone_numbers(phones) do
    level = if match?([_, _ | _], phones), do: :warning, else: :good
    finding(:phone_numbers, level, %{figures: %{phones: Enum.take(phones, @max_phones), phone_count: length(phones)}})
  end

  defp structured_data([]), do: finding(:structured_data, :warning)
  defp structured_data(types), do: finding(:structured_data, :good, %{figures: %{types: Enum.take(types, @max_types)}})

  defp language_declared(readable) do
    case Enum.reject(readable, &declares_language?/1) do
      [] -> finding(:language_declared, :good)
      undeclared -> finding(:language_declared, :warning, %{pages: Enum.map(undeclared, & &1.url)})
    end
  end

  defp declared_languages(readable) do
    case readable |> Enum.filter(&declares_language?/1) |> Enum.map(&String.trim(&1.facts["language"])) |> Enum.uniq() do
      [] -> []
      languages -> finding(:declared_languages, :good, %{figures: %{languages: languages}})
    end
  end

  defp declares_language?(page), do: is_binary(page.facts["language"]) and String.trim(page.facts["language"]) != ""

  defp business_profile(%{"checked" => true} = profile) do
    level = if profile["found"] == true and profile["links_to_site"] == true, do: :good, else: :warning

    finding(:business_profile, level, %{
      figures: %{
        name: profile["name"],
        found: profile["found"] == true,
        links_to_site: profile["links_to_site"] == true,
        title: profile["title"],
        rating: profile["rating"],
        votes: profile["votes"],
        claimed: profile["claimed"]
      }
    })
  end

  defp business_profile(%{"checked" => false} = profile),
    do: finding(:business_profile, :not_checked, %{figures: %{reason: profile["reason"]}})

  defp business_profile(_missing), do: []

  defp linking_sites(%{"checked" => true, "count" => count}) when is_integer(count) and count > 0,
    do: finding(:linking_sites, :good, %{figures: %{count: count}})

  defp linking_sites(%{"checked" => true, "count" => 0}), do: finding(:linking_sites, :warning, %{figures: %{count: 0}})

  defp linking_sites(%{"checked" => true}), do: finding(:linking_sites, :not_checked, %{figures: %{reason: @no_data}})

  defp linking_sites(%{"checked" => false} = fact),
    do: finding(:linking_sites, :not_checked, %{figures: %{reason: fact["reason"]}})

  defp linking_sites(_missing), do: []

  defp finding(check, level, attributes \\ %{}) when {check, level} in @check_levels,
    do: Finding.new(Map.merge(attributes, %{question: @question, check: check, level: level}))
end
