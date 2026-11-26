defmodule Dirmoon.WebPage.PublicUrlTest do
  use ExUnit.Case, async: true

  alias Dirmoon.WebPage.PublicUrl

  test "a public http or https address may be read" do
    for url <- [
          "https://lodowisko-testowe.example/cennik",
          "http://93.184.216.34/",
          "http://[2001:db8::1]/",
          "http://[::ffff:93.184.216.34]/"
        ] do
      assert PublicUrl.check(url) == {:ok, url}
    end
  end

  test "an address on an international host may be read, at the host's ASCII form" do
    assert PublicUrl.check("https://żółw.pl/oferta?strona=2") == {:ok, "https://xn--w-uga1v8h.pl/oferta?strona=2"}
    assert PublicUrl.check("https://例え.jp/") == {:ok, "https://xn--r8jz45g.jp/"}
    assert PublicUrl.check("https://xn--w-uga1v8h.pl/") == {:ok, "https://xn--w-uga1v8h.pl/"}
  end

  test "an address whose international host can't be encoded is refused" do
    for url <- ["https://-żółw.pl/", "https://١٢٣.com/", "https://#{String.duplicate("żółw.", 30)}pl/"] do
      assert {:error, "the address has no valid host name"} = PublicUrl.check(url), url
    end
  end

  test "full-width or ideographic spellings of localhost and of a loopback address are refused" do
    assert {:error, "a local address"} = PublicUrl.check("http://ｌｏｃａｌｈｏｓｔ/")
    assert {:error, "a local address"} = PublicUrl.check("http://admin．ｌｏｃａｌｈｏｓｔ/")

    for url <- ["http://１２７.０.０.１/", "http://127。0。0。1/", "http://１０．０．０．１/", "http://１６９.２５４.１６９.２５４/"] do
      assert {:error, "an address in a private network"} = PublicUrl.check(url), url
    end
  end

  test "an address that is not http or https, or has no host, is refused" do
    for url <- ["ftp://lodowisko-testowe.example/", "file:///etc/passwd", "javascript:alert(1)", "https://", "/cennik"] do
      assert {:error, "the address is not an http or https page"} = PublicUrl.check(url)
    end
  end

  test "an address longer than 2,048 bytes is refused" do
    too_long = "https://lodowisko-testowe.example/" <> String.duplicate("a", 2_048)

    assert PublicUrl.check(too_long) == {:error, "the address is too long"}
  end

  test "localhost and its subdomains are refused, whatever the case or a trailing dot" do
    for url <- ["http://localhost/", "http://LOCALHOST.:4000/", "https://admin.localhost/"] do
      assert {:error, "a local address"} = PublicUrl.check(url)
    end
  end

  test "loopback, private, link-local, shared and unspecified IP literals are refused" do
    for url <- [
          "http://127.0.0.1/",
          "http://127.1/",
          "http://2130706433/",
          "http://0.0.0.0/",
          "http://10.1.2.3/",
          "http://100.64.0.1/",
          "http://169.254.169.254/latest/meta-data/",
          "http://172.16.0.1/",
          "http://172.31.255.255/",
          "http://192.168.1.1/",
          "http://[::1]/",
          "http://[::]/",
          "http://[fd00::1]/",
          "http://[fe80::1]/",
          "http://[::ffff:127.0.0.1]/"
        ] do
      assert {:error, "an address in a private network"} = PublicUrl.check(url), url
    end
  end

  test "IPv4-compatible and NAT64 IPv6 literals are refused, whatever IPv4 address they carry" do
    for url <- [
          "http://[::127.0.0.1]/",
          "http://[::93.184.216.34]/",
          "http://[64:ff9b::7f00:1]/",
          "http://[64:ff9b::93.184.216.34]/"
        ] do
      assert {:error, "an address in a private network"} = PublicUrl.check(url), url
    end
  end

  test "addresses just outside the refused ranges may be read" do
    for url <- [
          "http://172.32.0.1/",
          "http://11.0.0.1/",
          "http://[fec0::1]/",
          "http://[::1:7f00:1]/",
          "http://[64:ff9b:0:0:1::7f00:1]/"
        ] do
      assert PublicUrl.check(url) == {:ok, url}
    end
  end
end
