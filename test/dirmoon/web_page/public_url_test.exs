defmodule Dirmoon.WebPage.PublicUrlTest do
  use ExUnit.Case, async: true

  alias Dirmoon.WebPage.PublicUrl

  test "a public http or https address may be read" do
    assert PublicUrl.check("https://lodowisko-testowe.example/cennik") == :ok
    assert PublicUrl.check("http://93.184.216.34/") == :ok
    assert PublicUrl.check("http://[2001:db8::1]/") == :ok
    assert PublicUrl.check("http://[::ffff:93.184.216.34]/") == :ok
  end

  test "an address that is not http or https, or has no host, is refused" do
    for url <- ["ftp://lodowisko-testowe.example/", "file:///etc/passwd", "javascript:alert(1)", "https://", "/cennik"] do
      assert {:error, "the address is not an http or https page"} = PublicUrl.check(url)
    end
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

  test "addresses just outside the refused ranges may be read" do
    assert PublicUrl.check("http://172.32.0.1/") == :ok
    assert PublicUrl.check("http://11.0.0.1/") == :ok
    assert PublicUrl.check("http://[fec0::1]/") == :ok
  end
end
