defmodule Dirmoon.WebPage.VisibleTextTest do
  use ExUnit.Case, async: true

  alias Dirmoon.WebPage.VisibleText

  test "only the text a visitor sees is kept, with whitespace collapsed" do
    html = """
    <!DOCTYPE html>
    <html><head><title>Cennik</title><style>body { color: red }</style></head>
    <body>
      <!-- ukryty komentarz 999 zł -->
      <script type="text/javascript">var cena = "999 zł";</script>
      <noscript>Włącz JavaScript</noscript>
      <template><p>Szablon 1 zł</p></template>
      <svg><text>Ikona</text></svg>
      <h1>Wypożyczalnia łyżew</h1>
      <p>Wypożyczenie łyżew:
         <strong>15&nbsp;zł</strong> za godzinę</p>
    </body></html>
    """

    assert VisibleText.from_html(html, 1_000) == "Wypożyczalnia łyżew Wypożyczenie łyżew: 15 zł za godzinę"
  end

  test "character references are decoded and unknown ones kept as written" do
    html =
      "<p>Ostrzenie &amp; serwis &ndash; 20&#160;z&#322; &#x142;y&#X17C;wy &bdquo;Hokej&rdquo; &unknown; &#1114112;</p>"

    assert VisibleText.from_html(html, 1_000) == "Ostrzenie & serwis – 20 zł łyżwy „Hokej” &unknown;"
  end

  test "the text is cut to the given length" do
    assert VisibleText.from_html("<p>Abcdefghij</p>", 4) == "Abcd"
  end

  test "bytes that are not UTF-8 do not break the text" do
    assert VisibleText.from_html(<<"Cena 10 z", 0xB3>>, 100) == "Cena 10 z"
  end

  test "every named character reference is decoded" do
    assert VisibleText.from_html("<p>Caf&eacute; &Uuml;ber &frac12;</p>", 100) == "Café Über ½"
  end

  test "a hidden element whose closing tag never comes hides the rest of the page, quickly" do
    for tag <- ["<script>", "<style>", "<head>"] do
      html = "<p>Pokoje</p>" <> String.duplicate(tag, div(1_000_000, byte_size(tag)))

      {microseconds, text} = :timer.tc(fn -> VisibleText.from_html(html, 1_000) end)

      assert text == "Pokoje"
      assert microseconds < 2_000_000
    end
  end

  test "hidden elements opened inside each other without end give no text, quickly" do
    for tag <- ["<noscript>", "<template>", "<svg>"] do
      html = "<p>Pokoje</p>" <> String.duplicate(tag, div(1_000_000, byte_size(tag)))

      {microseconds, text} = :timer.tc(fn -> VisibleText.from_html(html, 1_000) end)

      assert text == ""
      assert microseconds < 2_000_000
    end
  end

  test "the text of parsed elements leaves out hidden elements and comments" do
    tree = [{"h1", [], ["Pokoje ", {:comment, "ukryte"}, {"script", [], ["var a;"]}, {"em", [], ["nad\njeziorem"]}]}]

    assert VisibleText.from_tree(tree, 100) == "Pokoje nad jeziorem"
  end
end
