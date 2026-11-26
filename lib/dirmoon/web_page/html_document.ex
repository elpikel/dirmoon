defmodule Dirmoon.WebPage.HtmlDocument do
  @moduledoc """
  Parses a web page's HTML into a `LazyHTML` document the way a browser
  reads it: unclosed and misnested tags, character references, comments and
  the raw text of scripts and styles are all handled by the parser, in time
  linear in the page's size.

  The parser works within limits no real page reaches (nesting depth,
  attributes on one tag, memory and time), so a hostile page can't hold a
  worker. A page past any limit reads as an empty document. Bytes that are
  not UTF-8 are read as spaces.
  """

  @parse_limits [max_depth: 512, max_attributes: 200, max_memory: 100_000_000, timeout: 5_000]

  @doc "The document the HTML `html` describes, or an empty document when it is past the parser's limits."
  @spec parse(String.t()) :: LazyHTML.t()
  def parse(html) when is_binary(html) do
    html
    |> String.replace_invalid(" ")
    |> LazyHTML.from_document(@parse_limits)
  rescue
    _past_a_limit -> LazyHTML.from_document("")
  end
end
