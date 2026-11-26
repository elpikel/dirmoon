defmodule Dirmoon.WebPage.PageFacts do
  @moduledoc """
  The Page Facts of one web page: what dirmoon reads off its HTML without
  judging it. Pure: no I/O, and malformed or empty HTML gives a map with
  empty values, never an exception.

  The answer is a plain map with string keys, so it reads the same after a
  round trip through a `jsonb` column:

    * `"title"` and `"description"` (at most 1,000 bytes each),
      `"canonical"` (absolute), `"robots"` (the robots meta, lower-cased,
      at most 200 bytes) and `"language"` (the html `lang`, left out when
      longer than 35 bytes): a string or `nil`
    * `"noindex"`, `"viewport"`, `"password_field"`: booleans
    * `"main_headings"`: up to 50 h1 texts; `"sub_headings"`: up to 50
      `%{"level" => 2 | 3, "text" => text}`; each text at most 300 bytes
    * `"word_count"` and `"text_fingerprint"` (a hash of the normalised
      visible text, `nil` when there is none)
    * `"images"` and `"images_without_description"` (a blank or missing
      `alt`): counts
    * `"internal_links"` and `"external_links"`: web addresses
      (`Dirmoon.WebPage.WebAddress`: http(s), at most 2,048 bytes; the
      canonical too), de-duplicated, without fragments, an international
      host in its ASCII form (`Dirmoon.WebPage.HostName`); internal means
      the page's host, ignoring a leading `www.`. The first 100 internal links
      that fit in 64 KiB together and the first 50 external ones that fit
      in 16 KiB are kept: enough for a crawl to go on from
    * `"structured_data_types"`: up to 50 `@type`s in its JSON-LD, each at
      most 100 bytes; `"business_name"`: the `name` of a business described
      there (at most 300 bytes), or `nil`
    * `"phones"` (from `tel:` links, digits with a leading `+`) and
      `"emails"` (from `mailto:` links): up to 50 each, each at most 320
      bytes
    * `"ways_to_act"`: counts of `"phone_links"`, `"email_links"`,
      `"forms"` (with a field a visitor fills in) and `"button_links"`
      (links marked up as buttons)

  A text longer than its limit is cut at a character boundary; a type,
  phone or e-mail longer than its limit is left out, since a cut one would
  be wrong. So the text of any page's facts, counted in bytes as jsonb
  stores it (strings unescaped), stays under 160 KB: the links up to 82 KB,
  the headings up to 32 KB, phones and e-mails up to 33 KB, the types up to
  6 KB and the other texts under 6 KB. Written out as JSON text the same
  facts can be larger, since a quote, backslash or control character takes
  up to six bytes escaped.

  Every string fact is text a jsonb column can hold
  (`Dirmoon.JsonSafe.text/1`): the HTML is cleaned before it is parsed,
  and so are the strings decoded from JSON-LD and from percent escapes in
  `tel:` and `mailto:` links, so bytes that are not UTF-8 become U+FFFD and
  NUL characters are dropped.

  The HTML is parsed once, the way a browser reads it
  (`Dirmoon.WebPage.HtmlDocument`), and elements are found with CSS
  selectors; their text comes from `Dirmoon.WebPage.VisibleText`.

  The work stays linear in the page's size: the links, phones and e-mails
  are read from the first 5,000 distinct link addresses, and the structured
  data from the first 100 JSON-LD scripts and their first 10,000 items.
  Counts (images, phone and e-mail links, forms, button links) cover the
  whole page.
  """

  alias Dirmoon.JsonSafe
  alias Dirmoon.WebPage.HostName
  alias Dirmoon.WebPage.HtmlDocument
  alias Dirmoon.WebPage.VisibleText
  alias Dirmoon.WebPage.WebAddress

  @max_fragment_length 2_000
  @max_page_text_length 2_000_000
  @max_headings 50
  @max_heading_bytes 300
  @max_title_bytes 1_000
  @max_description_bytes 1_000
  @max_robots_bytes 200
  @max_language_bytes 35
  @max_business_name_bytes 300
  @max_types 50
  @compared_types 10
  @ways_to_act ~w(phone_links email_links forms button_links)
  @max_type_bytes 100
  @max_contacts 50
  @max_contact_bytes 320
  @internal_links_kept %{count: 100, bytes: 65_536}
  @external_links_kept %{count: 50, bytes: 16_384}
  @max_distinct_hrefs 5_000
  @max_json_ld_scripts 100
  @max_structured_data_nodes 10_000
  @web_schemes ["http", "https"]
  @json_ld_type "application/ld+json"
  @business_types ~w(Organization Corporation LocalBusiness ProfessionalService Store OnlineStore
    FoodEstablishment Restaurant LodgingBusiness Hotel MedicalBusiness Dentist LegalService
    HomeAndConstructionBusiness AutomotiveBusiness HealthAndBeautyBusiness SportsActivityLocation
    EntertainmentBusiness FinancialService TravelAgency EducationalOrganization)

  @word ~r/[\p{L}\p{N}]/u
  @whitespace ~r/\s+/u
  @phone_characters ~r/[^0-9]/
  @percent_escapes ~r/%([0-9a-fA-F]{2})/

  @doc "The Page Facts of `html`, read as the page at address `url`."
  @spec from_html(String.t(), String.t()) :: map()
  def from_html(html, url) when is_binary(html) and is_binary(url) do
    document = html |> JsonSafe.text() |> HtmlDocument.parse()
    page_text = document |> LazyHTML.to_tree() |> VisibleText.from_tree(@max_page_text_length)
    base = base_url(document, url)
    links = LazyHTML.query(document, "a[href]")
    hrefs = LazyHTML.attribute(links, "href")
    distinct_hrefs = hrefs |> Stream.uniq() |> Enum.take(@max_distinct_hrefs)
    structured_data = structured_data(document)
    headings = document |> LazyHTML.query("h1, h2, h3") |> LazyHTML.to_tree()

    %{
      "title" => document |> title() |> capped(@max_title_bytes),
      "description" => document |> meta_content("description") |> capped(@max_description_bytes),
      "canonical" => canonical(document, base),
      "language" => language(document),
      "viewport" => document |> named_metas("viewport") |> Enum.any?(),
      "main_headings" => headings |> headings(["h1"]) |> Enum.map(& &1["text"]),
      "sub_headings" => headings(headings, ["h2", "h3"]),
      "word_count" => word_count(page_text),
      "text_fingerprint" => text_fingerprint(page_text),
      "password_field" => document |> elements("input[type]") |> Enum.any?(&(input_type(&1) == "password"))
    }
    |> Map.merge(robots(document))
    |> Map.merge(images(document))
    |> Map.merge(links(distinct_hrefs, base))
    |> Map.merge(%{
      "structured_data_types" =>
        structured_data
        |> Stream.flat_map(&types/1)
        |> Stream.reject(&(byte_size(&1) > @max_type_bytes))
        |> Stream.uniq()
        |> Enum.take(@max_types),
      "business_name" => structured_data |> Enum.find_value(&business_name/1) |> capped(@max_business_name_bytes),
      "phones" =>
        distinct_hrefs
        |> Stream.filter(&scheme?(&1, "tel:"))
        |> Stream.map(&phone/1)
        |> Stream.reject(&(&1 == ""))
        |> contacts(),
      "emails" => distinct_hrefs |> Stream.filter(&scheme?(&1, "mailto:")) |> Stream.flat_map(&emails/1) |> contacts(),
      "ways_to_act" => %{
        "phone_links" => Enum.count(hrefs, &scheme?(&1, "tel:")),
        "email_links" => Enum.count(hrefs, &scheme?(&1, "mailto:")),
        "forms" => document |> LazyHTML.query("form") |> Enum.count(&fillable_form?/1),
        "button_links" => links |> attribute_maps() |> Enum.count(&button_link?/1)
      }
    })
  end

  @doc """
  The few Page Facts that compare one page with another (a site's page
  with a Competitor Page), from Page Facts as `from_html/2` gives them or
  as stored: `"word_count"`, `"main_heading_count"`, `"sub_heading_count"`,
  `"structured_data_types"` (the first #{@compared_types}), `"images"`, `"title_length"`
  (in characters) and `"ways_to_act"` (its four counts). A fact missing or
  of an unexpected type is `nil` (no types is an empty list), never a
  guess. A few hundred bytes, whatever the page.
  """
  @spec comparison(map()) :: map()
  def comparison(facts) when is_map(facts) do
    %{
      "word_count" => count(facts["word_count"]),
      "main_heading_count" => list_length(facts["main_headings"]),
      "sub_heading_count" => list_length(facts["sub_headings"]),
      "structured_data_types" =>
        facts["structured_data_types"]
        |> List.wrap()
        |> Enum.filter(&(is_binary(&1) and byte_size(&1) <= @max_type_bytes))
        |> Enum.take(@compared_types),
      "images" => count(facts["images"]),
      "title_length" => title_length(facts["title"]),
      "ways_to_act" => compared_ways_to_act(facts["ways_to_act"])
    }
  end

  defp count(value) when is_integer(value) and value >= 0, do: value
  defp count(_not_a_count), do: nil

  defp list_length(list) when is_list(list), do: length(list)
  defp list_length(_not_a_list), do: nil

  defp title_length(title) when is_binary(title), do: String.length(title)
  defp title_length(_no_title), do: nil

  defp compared_ways_to_act(ways) when is_map(ways), do: Map.new(@ways_to_act, &{&1, count(ways[&1])})

  defp compared_ways_to_act(_missing), do: nil

  defp title(document) do
    document
    |> LazyHTML.query("title:not(svg title)")
    |> LazyHTML.to_tree()
    |> Enum.take(1)
    |> text_of()
    |> non_blank()
  end

  defp headings(heading_tree, tags) do
    heading_tree
    |> Stream.filter(fn {tag, _attributes, _children} -> tag in tags end)
    |> Stream.map(fn {"h" <> level, _attributes, _children} = heading ->
      %{"level" => String.to_integer(level), "text" => [heading] |> text_of() |> JsonSafe.text(@max_heading_bytes)}
    end)
    |> Stream.reject(&(&1["text"] == ""))
    |> Enum.take(@max_headings)
  end

  defp meta_content(document, name) do
    document
    |> named_metas(name)
    |> Enum.find_value(&(&1 |> Map.get("content", "") |> attribute_text() |> non_blank()))
  end

  defp named_metas(document, name) do
    document
    |> elements("meta[name]")
    |> Enum.filter(&(&1 |> Map.fetch!("name") |> String.downcase() == name))
  end

  defp robots(document) do
    robots = document |> meta_content("robots") |> downcase()
    directives = String.split(robots || "", ~r/[\s,]+/, trim: true)

    %{"robots" => capped(robots, @max_robots_bytes), "noindex" => "noindex" in directives or "none" in directives}
  end

  defp canonical(document, base) do
    document
    |> elements("link[rel]")
    |> Enum.find(&("canonical" in rel_values(&1)))
    |> case do
      %{"href" => href} -> web_address(href, base)
      _none -> nil
    end
  end

  defp rel_values(attributes), do: attributes |> Map.fetch!("rel") |> String.downcase() |> String.split()

  defp language(document) do
    document
    |> elements("html")
    |> Enum.find_value(&(&1 |> Map.get("lang", "") |> non_blank()))
    |> case do
      language when is_binary(language) and byte_size(language) <= @max_language_bytes -> language
      _missing_or_too_long -> nil
    end
  end

  defp images(document) do
    images = elements(document, "img")
    without_description = Enum.count(images, &(non_blank(Map.get(&1, "alt", "")) == nil))

    %{"images" => Enum.count(images), "images_without_description" => without_description}
  end

  defp base_url(document, url) do
    page_base = parse_base(url)

    with [%{"href" => href}] <- document |> elements("base[href]") |> Enum.take(1),
         address when is_binary(address) <- web_address(href, page_base) do
      URI.parse(address)
    else
      _no_base -> page_base
    end
  end

  defp parse_base(url) do
    with {:ok, uri} <- URI.new(url),
         true <- web_uri?(uri) do
      uri
    else
      _not_a_web_address -> nil
    end
  end

  defp web_uri?(%URI{scheme: scheme, host: host}), do: scheme in @web_schemes and is_binary(host) and host != ""

  defp links(distinct_hrefs, base) do
    page_host = base && HostName.bare(base.host)

    {internal, external} =
      distinct_hrefs
      |> Enum.map(&web_address(&1, base))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.split_with(&(page_host != nil and HostName.bare(URI.parse(&1).host) == page_host))

    %{
      "internal_links" => kept_links(internal, @internal_links_kept),
      "external_links" => kept_links(external, @external_links_kept)
    }
  end

  defp kept_links(links, %{count: count, bytes: bytes}) do
    links
    |> Enum.take(count)
    |> Enum.reduce_while(%{kept: [], bytes_left: bytes}, fn link, %{kept: kept, bytes_left: bytes_left} ->
      if byte_size(link) <= bytes_left,
        do: {:cont, %{kept: [link | kept], bytes_left: bytes_left - byte_size(link)}},
        else: {:halt, %{kept: kept, bytes_left: bytes_left}}
    end)
    |> Map.fetch!(:kept)
    |> Enum.reverse()
  end

  defp contacts(contacts) do
    contacts
    |> Stream.reject(&(byte_size(&1) > @max_contact_bytes))
    |> Stream.uniq()
    |> Enum.take(@max_contacts)
  end

  defp web_address(href, base) do
    with {:ok, ascii_href} <- href |> String.trim() |> WebAddress.with_ascii_host(),
         {:ok, reference} <- URI.new(ascii_href),
         address = resolve(reference, base),
         true <- web_uri?(address),
         web_address = URI.to_string(%{address | fragment: nil, host: String.downcase(address.host)}),
         true <- WebAddress.acceptable?(web_address) do
      web_address
    else
      _not_a_web_address -> nil
    end
  end

  defp resolve(%URI{scheme: nil} = reference, %URI{} = base), do: URI.merge(base, reference)
  defp resolve(reference, _base), do: reference

  defp scheme?(href, scheme), do: href |> String.trim_leading() |> String.downcase() |> String.starts_with?(scheme)

  defp phone(href) do
    number = href |> after_scheme() |> String.split(";") |> hd() |> percent_decode() |> String.trim()
    digits = String.replace(number, @phone_characters, "")

    if digits != "" and String.starts_with?(number, "+"), do: "+" <> digits, else: digits
  end

  defp emails(href) do
    href
    |> after_scheme()
    |> String.split("?")
    |> hd()
    |> percent_decode()
    |> String.split(",")
    |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
    |> Enum.filter(&String.contains?(&1, "@"))
  end

  defp percent_decode(text) do
    @percent_escapes
    |> Regex.replace(text, fn _escape, hex -> <<String.to_integer(hex, 16)>> end)
    |> String.replace_invalid(" ")
    |> JsonSafe.text()
  end

  defp after_scheme(href), do: href |> String.trim() |> String.split(":", parts: 2) |> List.last()

  defp fillable_form?(form) do
    Enum.any?(elements(form, "input"), &(input_type(&1) != "hidden")) or
      form |> LazyHTML.query("textarea, select") |> Enum.any?()
  end

  defp input_type(attributes), do: attributes |> Map.get("type", "text") |> String.downcase()

  defp button_link?(attributes) do
    classes = attributes |> Map.get("class", "") |> String.downcase()

    downcase(Map.get(attributes, "role")) == "button" or String.contains?(classes, ["btn", "button"])
  end

  defp structured_data(document) do
    document
    |> LazyHTML.query("script[type]")
    |> Stream.filter(&json_ld?/1)
    |> Stream.take(@max_json_ld_scripts)
    |> Stream.flat_map(fn script ->
      case Jason.decode(LazyHTML.text(script)) do
        {:ok, data} -> nodes([data])
        {:error, _invalid} -> []
      end
    end)
    |> Enum.take(@max_structured_data_nodes)
  end

  defp json_ld?(script) do
    [type] = LazyHTML.attribute(script, "type")
    type |> String.trim() |> String.downcase() == @json_ld_type
  end

  defp nodes(values) do
    Stream.flat_map(values, fn
      list when is_list(list) -> nodes(list)
      map when is_map(map) -> Stream.concat([map], map |> Map.values() |> nodes())
      _value -> []
    end)
  end

  defp types(node) do
    node
    |> Map.get("@type")
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&JsonSafe.text/1)
  end

  defp business_name(node) do
    with true <- Enum.any?(types(node), &(&1 in @business_types)),
         name when is_binary(name) <- node["name"] do
      name |> JsonSafe.text() |> non_blank()
    else
      _not_a_named_business -> nil
    end
  end

  defp word_count(page_text), do: page_text |> String.split() |> Enum.count(&(&1 =~ @word))

  defp text_fingerprint(""), do: nil

  defp text_fingerprint(page_text) do
    normalised = page_text |> String.downcase() |> String.replace(@whitespace, " ")
    :sha256 |> :crypto.hash(normalised) |> Base.encode16(case: :lower)
  end

  defp elements(document, selector) do
    document
    |> LazyHTML.query(selector)
    |> attribute_maps()
  end

  defp attribute_maps(elements) do
    elements
    |> LazyHTML.attributes()
    |> Stream.map(&Map.new/1)
  end

  defp text_of(tree), do: VisibleText.from_tree(tree, @max_fragment_length)

  defp attribute_text(value), do: text_of([value])

  defp non_blank(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp capped(nil, _max_bytes), do: nil
  defp capped(text, max_bytes), do: JsonSafe.text(text, max_bytes)

  defp downcase(nil), do: nil
  defp downcase(text), do: String.downcase(text)
end
