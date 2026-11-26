defmodule Dirmoon.WebPage do
  @moduledoc """
  The seam to the public web: reads one web page. The adapter is chosen by
  `config :dirmoon, :web_page_adapter`; it needs no credentials, so the real
  adapter (`Dirmoon.WebPage.HTTP`) is the default outside test.

  `fetch_text/1` answers a page's visible `text` and the `url` actually read
  (after redirects), for a Price Check to look for prices in; any answer
  other than a 200 HTML or plain-text page is an error.

  `fetch/1` answers the page raw, for a Site Scan: the final `url`, its HTTP
  `status` (a 404 or 500 is an answer too, not an error), the `redirects`
  (every address visited before the final one, in order), the
  `content_type` (the media type, lower-cased, without parameters; `nil`
  when the answer has none) and the `body`. The body is read for HTML,
  XHTML, plain text and XML; any other content type answers an empty body,
  so a link to a PDF can be recorded as not a page.

  `text_page/1` turns a raw page into what `fetch_text/1` answers, so a
  caller that needs both the raw page and its text reads the page once.
  """

  alias Dirmoon.WebPage.VisibleText

  @max_text_length 15_000
  @text_content_types ["text/html", "application/xhtml+xml", "text/plain"]
  @html_content_types ["text/html", "application/xhtml+xml"]

  @type page :: %{text: String.t(), url: String.t()}

  @type raw_page :: %{
          url: String.t(),
          status: non_neg_integer(),
          redirects: [String.t()],
          content_type: String.t() | nil,
          body: String.t()
        }

  @callback fetch_text(String.t()) :: {:ok, page()} | {:error, String.t()}

  @callback fetch(String.t()) :: {:ok, raw_page()} | {:error, String.t()}

  @doc "Reads the visible text of the page at `url` through the configured adapter."
  @spec fetch_text(String.t()) :: {:ok, page()} | {:error, String.t()}
  def fetch_text(url) when is_binary(url), do: adapter().fetch_text(url)

  @doc "Reads the page at `url` raw through the configured adapter."
  @spec fetch(String.t()) :: {:ok, raw_page()} | {:error, String.t()}
  def fetch(url) when is_binary(url), do: adapter().fetch(url)

  @doc """
  What `fetch_text/1` answers for a page `fetch/1` read: the visible text
  (`Dirmoon.WebPage.VisibleText`, at most #{@max_text_length} characters, a
  length the LLM can take) of a 200 HTML or plain-text answer, with the
  address read; `{:error, "not an HTML page"}` for another 200 answer, and
  `{:error, "HTTP <status>"}` for any other status.
  """
  @spec text_page(raw_page()) :: {:ok, page()} | {:error, String.t()}
  def text_page(%{status: 200, content_type: content_type, body: body, url: url})
      when content_type in @text_content_types,
      do: {:ok, %{text: VisibleText.from_html(body, @max_text_length), url: url}}

  def text_page(%{status: 200}), do: {:error, "not an HTML page"}
  def text_page(%{status: status}), do: {:error, "HTTP #{status}"}

  @doc "Whether a page `fetch/1` read is HTML (or XHTML), so it has Page Facts."
  @spec html?(raw_page()) :: boolean()
  def html?(%{content_type: content_type}), do: content_type in @html_content_types

  defp adapter, do: Application.fetch_env!(:dirmoon, :web_page_adapter)
end
