defmodule Dirmoon.WebPage.PageFactsSpeedTest do
  use ExUnit.Case, async: false

  alias Dirmoon.WebPage.PageFacts

  @url "https://hotel-testowy.example/pokoje/"

  test "a page of script tags that never close is read quickly" do
    html = String.duplicate("<script>", div(1_000_000, 8))

    {microseconds, facts} = :timer.tc(fn -> PageFacts.from_html(html, @url) end)

    assert facts["word_count"] == 0
    assert microseconds < 60_000_000
  end

  test "a page of title tags that never close is read quickly" do
    html = String.duplicate("<title>", div(1_000_000, 7))

    {microseconds, facts} = :timer.tc(fn -> PageFacts.from_html(html, @url) end)

    assert String.starts_with?(facts["title"], "<title><title>")
    assert microseconds < 60_000_000
  end

  test "a page of main heading tags that never close is read quickly" do
    html = String.duplicate("<h1>", div(1_000_000, 4))

    {microseconds, facts} = :timer.tc(fn -> PageFacts.from_html(html, @url) end)

    assert facts["main_headings"] == []
    assert microseconds < 60_000_000
  end

  test "a page of main headings that never close is read quickly" do
    html = String.duplicate("<h1>Pokój", div(2_000_000, 10))

    {microseconds, facts} = :timer.tc(fn -> PageFacts.from_html(html, @url) end)

    assert facts["main_headings"] == List.duplicate("Pokój", 50)
    assert microseconds < 60_000_000
  end

  test "a page of two megabytes of the same link is read quickly" do
    html = String.duplicate("<a href=/x>", div(2_000_000, 11))

    {microseconds, facts} = :timer.tc(fn -> PageFacts.from_html(html, @url) end)

    assert facts["internal_links"] == ["https://hotel-testowy.example/x"]
    assert microseconds < 60_000_000
  end

  test "a page of two megabytes of different links is read quickly and keeps a hundred of them" do
    html = Enum.map_join(1..div(2_000_000, 16), &"<a href=/#{&1}>")

    {microseconds, facts} = :timer.tc(fn -> PageFacts.from_html(html, @url) end)

    assert facts["internal_links"] == Enum.map(1..100, &"https://hotel-testowy.example/#{&1}")
    assert microseconds < 60_000_000
  end

  test "a page of two megabytes of the same phone link is read quickly and counts every link" do
    links = div(2_000_000, 17)
    html = String.duplicate(~s(<a href="tel:+1">), links)

    {microseconds, facts} = :timer.tc(fn -> PageFacts.from_html(html, @url) end)

    assert facts["phones"] == ["+1"]
    assert facts["ways_to_act"]["phone_links"] == links
    assert microseconds < 60_000_000
  end

  test "a page of two megabytes of different phone links is read quickly and keeps the first fifty phones" do
    html = Enum.map_join(1..div(2_000_000, 22), &~s(<a href="tel:+#{&1}">))

    {microseconds, facts} = :timer.tc(fn -> PageFacts.from_html(html, @url) end)

    assert facts["phones"] == Enum.map(1..50, &"+#{&1}")
    assert microseconds < 60_000_000
  end

  test "a page of two megabytes of images is read quickly and counts every image" do
    images = div(2_000_000, 5)
    html = String.duplicate("<img>", images)

    {microseconds, facts} = :timer.tc(fn -> PageFacts.from_html(html, @url) end)

    assert facts["images"] == images
    assert facts["images_without_description"] == images
    assert microseconds < 60_000_000
  end

  test "a page of two megabytes of JSON-LD scripts is read quickly and keeps the first fifty types" do
    script = &~s(<script type="application/ld+json">{"@type": ["Hotel", "Typ#{&1}"], "name": "Hotel Testowy"}</script>)
    html = Enum.map_join(1..div(2_000_000, byte_size(script.(100_000))), script)

    {microseconds, facts} = :timer.tc(fn -> PageFacts.from_html(html, @url) end)

    assert facts["structured_data_types"] == ["Hotel" | Enum.map(1..49, &"Typ#{&1}")]
    assert facts["business_name"] == "Hotel Testowy"
    assert microseconds < 60_000_000
  end

  test "a page of two megabytes of structured data in one script is read quickly" do
    item = ~s({"@type": "Offer", "name": "Pokój"})
    items = Enum.map_join(1..div(2_000_000, byte_size(item) + 1), ",", fn _item -> item end)
    html = ~s(<script type="application/ld+json">[#{items}]</script>)

    {microseconds, facts} = :timer.tc(fn -> PageFacts.from_html(html, @url) end)

    assert facts["structured_data_types"] == ["Offer"]
    assert microseconds < 60_000_000
  end

  test "a page of two megabytes of e-mail links, forms and inputs is read quickly" do
    html = String.duplicate(~s(<a href="mailto:a@b.example">), 40_000) <> String.duplicate("<form><input></form>", 60_000)

    {microseconds, facts} = :timer.tc(fn -> PageFacts.from_html(html, @url) end)

    assert facts["emails"] == ["a@b.example"]
    assert facts["ways_to_act"]["email_links"] == 40_000
    assert facts["ways_to_act"]["forms"] == 60_000
    assert microseconds < 60_000_000
  end
end
