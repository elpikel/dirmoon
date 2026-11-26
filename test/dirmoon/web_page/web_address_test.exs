defmodule Dirmoon.WebPage.WebAddressTest do
  use ExUnit.Case, async: true

  alias Dirmoon.WebPage.WebAddress

  test "an http or https address with a host of at most 2,048 bytes is acceptable" do
    longest = "https://hotel-testowy.example/" <> String.duplicate("a", 2_048 - 30)

    assert WebAddress.acceptable?("https://hotel-testowy.example/pokoje?a=1")
    assert WebAddress.acceptable?("http://hotel-testowy.example")
    assert WebAddress.acceptable?(longest)
    refute WebAddress.too_long?(longest)
  end

  test "an address longer than 2,048 bytes is not acceptable" do
    too_long = "https://hotel-testowy.example/" <> String.duplicate("a", 2_048 - 29)

    assert WebAddress.too_long?(too_long)
    refute WebAddress.acceptable?(too_long)
  end

  test "an address that is not http or https, has no host or can't be parsed is not acceptable" do
    refute WebAddress.acceptable?("ftp://hotel-testowy.example/")
    refute WebAddress.acceptable?("/pokoje")
    refute WebAddress.acceptable?("https:///pokoje")
    refute WebAddress.acceptable?("https://hotel-testowy.example/z spacją")
    refute WebAddress.acceptable?("")
  end

  test "an address on an international host is acceptable, and one whose host can't be encoded is not" do
    assert WebAddress.acceptable?("https://żółw.pl/oferta")
    assert WebAddress.acceptable?("https://例え.jp")
    refute WebAddress.acceptable?("https://-żółw.pl/oferta")
  end
end
