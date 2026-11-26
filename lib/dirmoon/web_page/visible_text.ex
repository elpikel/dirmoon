defmodule Dirmoon.WebPage.VisibleText do
  @moduledoc """
  Turns HTML into the text a visitor sees: comments and the `head`,
  `script`, `style`, `noscript`, `template` and `svg` elements are dropped,
  every tag becomes a space, character references are decoded and
  whitespace is collapsed to single spaces. Bytes that are not UTF-8 and
  references to no character are dropped. The result is cut to
  `max_length` characters.

  `from_html/2` parses the page first (`Dirmoon.WebPage.HtmlDocument`);
  `from_tree/2` takes elements already parsed, as `LazyHTML.to_tree/1`
  gives them, so a page is parsed once.
  """

  alias Dirmoon.WebPage.HtmlDocument

  @hidden_elements ~w(head script style noscript template svg)
  @spaces ~r/[\s\x{FFFD}]+/u

  @doc "The visible text of `html`, at most `max_length` characters."
  @spec from_html(String.t(), pos_integer()) :: String.t()
  def from_html(html, max_length) when is_binary(html) and is_integer(max_length) and max_length > 0 do
    html
    |> HtmlDocument.parse()
    |> LazyHTML.to_tree()
    |> from_tree(max_length)
  end

  @doc "The visible text of the parsed nodes `tree`, at most `max_length` characters."
  @spec from_tree(LazyHTML.Tree.t(), pos_integer()) :: String.t()
  def from_tree(tree, max_length) when is_list(tree) and is_integer(max_length) and max_length > 0 do
    case tree |> collect_texts([]) |> Enum.reverse() do
      [] -> ""
      texts -> texts |> Enum.join(" ") |> String.replace(@spaces, " ") |> String.trim() |> String.slice(0, max_length)
    end
  end

  defp collect_texts(nodes, texts), do: Enum.reduce(nodes, texts, &collect_node_texts/2)

  defp collect_node_texts(text, texts) when is_binary(text), do: [text | texts]

  defp collect_node_texts({tag, _attributes, children}, texts) when tag not in @hidden_elements,
    do: collect_texts(children, texts)

  defp collect_node_texts(_hidden_element_or_comment, texts), do: texts
end
