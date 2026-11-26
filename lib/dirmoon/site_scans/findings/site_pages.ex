defmodule Dirmoon.SiteScans.Findings.SitePages do
  @moduledoc """
  Which Scanned Pages a Finding's rule looks at, shared by the rule modules
  under `Dirmoon.SiteScans.Findings`.

    * `readable/1`: the site's own readable HTML pages
      (`Dirmoon.SiteScans.ScannedPage.readable?/1`)
    * `own_pages/1`: the readable pages that are pages of their own, not
      variants of another address (`variant?/1`)
    * `with_content/1`: those Google may list, i.e. without `noindex`; the
      content checks look at these only
    * `variant?/1`: the page's `canonical` names a different address
      (`same_address?/2`): it says it is a copy of that page
    * `same_address?/2`: two addresses name the same page once the scheme
      (http or https), host case, a leading `www.`, the Unicode or ASCII
      form of an international host, a trailing slash and a fragment are
      set aside
    * `little_text?/1`: fewer than 150 words, unless the page declares a
      language written without spaces between words (Chinese, Japanese,
      Thai, Lao, Khmer, Burmese, Tibetan), whose word count says nothing
    * `home_page?/2`: the page is the scan's home page, by its address or the
      address its read ended at
  """

  alias Dirmoon.SiteScans.ScannedPage
  alias Dirmoon.WebPage.HostName

  @little_text_words 150
  @languages_without_spaces ~w(zh ja th lo km my bo)

  @doc "The site's own readable HTML pages."
  def readable(pages), do: Enum.filter(pages, &ScannedPage.readable?/1)

  @doc "The readable pages that are not variants of another address."
  def own_pages(pages), do: pages |> readable() |> Enum.reject(&variant?/1)

  @doc "The readable pages of their own without `noindex`."
  def with_content(pages), do: pages |> own_pages() |> Enum.reject(&(&1.facts["noindex"] == true))

  @doc "Whether the page's `canonical` names an address other than its own (or the one its read ended at)."
  def variant?(%{url: url, facts: facts}) do
    case facts["canonical"] do
      canonical when is_binary(canonical) and canonical != "" ->
        not (same_address?(canonical, url) or same_address?(canonical, facts["final_url"]))

      _none ->
        false
    end
  end

  @doc "Whether two addresses name the same page (see the module doc); anything but two strings is not."
  def same_address?(address, other) when is_binary(address) and is_binary(other),
    do: normalised(address) == normalised(other)

  def same_address?(_address, _other), do: false

  @doc "Whether the page's word count can be judged: its declared language, if any, puts spaces between words."
  def words_countable?(page) do
    case page.facts["language"] do
      language when is_binary(language) ->
        language |> String.downcase() |> String.split(["-", "_"]) |> hd() |> then(&(&1 not in @languages_without_spaces))

      _undeclared ->
        true
    end
  end

  @doc "Whether the page holds very little text, judged only when its words can be counted."
  def little_text?(page) do
    words_countable?(page) and is_integer(page.facts["word_count"]) and page.facts["word_count"] < @little_text_words
  end

  @doc "Whether the page is the home page `home_page` (an address, or nil while unknown)."
  def home_page?(_page, nil), do: false
  def home_page?(page, home_page), do: page.url == home_page or page.facts["final_url"] == home_page

  defp normalised(address) do
    %URI{host: host, path: path} = uri = address |> String.trim() |> URI.parse()

    %{
      host: host |> to_string() |> HostName.bare(),
      path: path |> to_string() |> String.trim_trailing("/"),
      query: uri.query
    }
  end
end
