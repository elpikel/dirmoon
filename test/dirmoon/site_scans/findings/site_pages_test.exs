defmodule Dirmoon.SiteScans.Findings.SitePagesTest do
  use ExUnit.Case, async: true

  alias Dirmoon.SiteScans.Findings.SitePages

  test "an address on an international host names the same page in its Unicode and ASCII forms" do
    assert SitePages.same_address?("https://www.Żółw.pl/oferta/", "http://xn--w-uga1v8h.pl/oferta")
    refute SitePages.same_address?("https://żółw.pl/oferta", "https://xn--mnchen-3ya.de/oferta")
  end
end
