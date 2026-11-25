defmodule Dirmoon.WebPage.VisibleText do
  @moduledoc """
  Turns an HTML document into the text a visitor sees: comments and the
  `head`, `script`, `style`, `noscript`, `template` and `svg` elements are
  dropped, every tag becomes a space, common character references are
  decoded and whitespace is collapsed to single spaces. Text that isn't
  valid UTF-8 has its invalid bytes replaced. The result is cut to
  `max_length` characters.
  """

  @hidden_elements ~r/<(head|script|style|noscript|template|svg)\b[^>]*>.*?<\/\1\s*>/is
  @comments ~r/<!--.*?-->/s
  @tags ~r/<[^>]*>/s
  @character_references ~r/&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z]+);/
  @whitespace ~r/\s+/u
  @named_characters %{
    "amp" => "&",
    "lt" => "<",
    "gt" => ">",
    "quot" => "\"",
    "apos" => "'",
    "nbsp" => " ",
    "shy" => "",
    "ndash" => "–",
    "mdash" => "—",
    "hellip" => "…",
    "euro" => "€",
    "bdquo" => "„",
    "ldquo" => "“",
    "rdquo" => "”",
    "lsquo" => "‘",
    "rsquo" => "’",
    "laquo" => "«",
    "raquo" => "»",
    "oacute" => "ó",
    "Oacute" => "Ó"
  }

  @doc "The visible text of `html`, at most `max_length` characters."
  def from_html(html, max_length) when is_binary(html) and is_integer(max_length) and max_length > 0 do
    html
    |> String.replace_invalid(" ")
    |> String.replace(@comments, " ")
    |> String.replace(@hidden_elements, " ")
    |> String.replace(@tags, " ")
    |> String.replace(@character_references, &character/1)
    |> String.replace(@whitespace, " ")
    |> String.trim()
    |> String.slice(0, max_length)
  end

  defp character("&#x" <> hex), do: hex |> String.trim_trailing(";") |> String.to_integer(16) |> codepoint()
  defp character("&#X" <> hex), do: hex |> String.trim_trailing(";") |> String.to_integer(16) |> codepoint()
  defp character("&#" <> decimal), do: decimal |> String.trim_trailing(";") |> String.to_integer() |> codepoint()

  defp character("&" <> named = reference) do
    Map.get(@named_characters, String.trim_trailing(named, ";"), reference)
  end

  defp codepoint(number) do
    case :unicode.characters_to_binary([number]) do
      text when is_binary(text) -> text
      _not_a_character -> " "
    end
  end
end
