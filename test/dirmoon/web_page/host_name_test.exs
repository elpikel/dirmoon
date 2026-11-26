defmodule Dirmoon.WebPage.HostNameTest do
  use ExUnit.Case, async: true

  alias Dirmoon.WebPage.HostName

  test "an international host name is turned into its ASCII form" do
    assert HostName.to_ascii("żółw.pl") == {:ok, "xn--w-uga1v8h.pl"}
    assert HostName.to_ascii("MÜNCHEN.de") == {:ok, "xn--mnchen-3ya.de"}
    assert HostName.to_ascii("例え.jp") == {:ok, "xn--r8jz45g.jp"}
  end

  test "an ASCII host name is left as it is" do
    assert HostName.to_ascii("Hotel-Testowy.example") == {:ok, "Hotel-Testowy.example"}
    assert HostName.to_ascii("::1") == {:ok, "::1"}
  end

  test "full-width and ideographic digits, letters and dots become their ASCII form" do
    assert HostName.to_ascii("１２７.０.０.１") == {:ok, "127.0.0.1"}
    assert HostName.to_ascii("127。0。0。1") == {:ok, "127.0.0.1"}
    assert HostName.to_ascii("ｌｏｃａｌｈｏｓｔ") == {:ok, "localhost"}
  end

  test "an international name that can't be encoded has no ASCII form" do
    assert HostName.to_ascii("-żółw.pl") == :error
    assert HostName.to_ascii("١٢٣.com") == :error
    assert HostName.to_ascii(String.duplicate("ż", 70) <> ".pl") == :error
    assert HostName.to_ascii(String.duplicate("żółw.", 30) <> "pl") == :error
  end

  test "the canonical form is the lower-case ASCII form, or the name lower-cased when it has none" do
    assert HostName.canonical("ŻÓŁW.pl") == "xn--w-uga1v8h.pl"
    assert HostName.canonical("WWW.Hotel-Testowy.example") == "www.hotel-testowy.example"
    assert HostName.canonical("-ŻÓŁW.pl") == "-żółw.pl"
  end

  test "the bare form drops a leading www, so the Unicode and ASCII spellings of one site are equal" do
    assert HostName.bare("www.żółw.pl") == "xn--w-uga1v8h.pl"
    assert HostName.bare("ｗｗｗ.żółw.pl") == "xn--w-uga1v8h.pl"
    assert HostName.bare("WWW.xn--w-uga1v8h.pl") == "xn--w-uga1v8h.pl"
  end

  test "an ASCII-encoded name reads in its Unicode form, and anything else as it is" do
    assert HostName.to_unicode("xn--w-uga1v8h.pl") == "żółw.pl"
    assert HostName.to_unicode("www.xn--mnchen-3ya.de") == "www.münchen.de"
    assert HostName.to_unicode("hotel-testowy.example") == "hotel-testowy.example"
    assert HostName.to_unicode("xn--zz.pl") == "xn--zz.pl"
    assert HostName.to_unicode(nil) == nil
  end
end
