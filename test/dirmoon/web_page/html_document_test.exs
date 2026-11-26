defmodule Dirmoon.WebPage.HtmlDocumentTest do
  use ExUnit.Case, async: true

  alias Dirmoon.WebPage.HtmlDocument

  @empty_document [{"html", [], [{"head", [], []}, {"body", [], []}]}]

  test "a page is parsed the way a browser reads it" do
    document = HtmlDocument.parse(~s(<title>Caf&eacute;</title><p title="a>b">Pokoje))

    assert LazyHTML.to_tree(document) == [
             {"html", [],
              [{"head", [], [{"title", [], ["Café"]}]}, {"body", [], [{"p", [{"title", "a>b"}], ["Pokoje"]}]}]}
           ]
  end

  test "bytes that are not UTF-8 are read as spaces" do
    document = HtmlDocument.parse(<<"<p>Cena 10 z", 0xB3, "</p>">>)

    assert LazyHTML.text(document) == "Cena 10 z "
  end

  test "a page nested deeper than a browser page ever is reads as an empty document" do
    document = HtmlDocument.parse(String.duplicate("<div>", 1_000) <> "<h1>Pokoje</h1>")

    assert LazyHTML.to_tree(document) == @empty_document
  end

  test "a page that takes more memory to parse than a real page does reads as an empty document" do
    document = HtmlDocument.parse(String.duplicate("<p>x", 1_000_000))

    assert LazyHTML.to_tree(document) == @empty_document
  end

  test "a tag with more attributes than a real page uses reads as an empty document" do
    attributes = Enum.map_join(1..1_000, " ", &"data-a#{&1}=x")

    assert "<p #{attributes}>Pokoje</p>" |> HtmlDocument.parse() |> LazyHTML.to_tree() == @empty_document
  end
end
