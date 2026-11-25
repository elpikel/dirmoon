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
end
