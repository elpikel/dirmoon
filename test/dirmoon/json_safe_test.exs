defmodule Dirmoon.JsonSafeTest do
  use ExUnit.Case, async: true

  alias Dirmoon.JsonSafe

  test "a decimal becomes its decimal string, without exponent" do
    assert JsonSafe.encode(Decimal.new("0.66")) == "0.66"
    assert JsonSafe.encode(Decimal.new("1E+2")) == "100"
  end

  test "dates and times become ISO 8601 strings" do
    assert JsonSafe.encode(~D[2026-11-24]) == "2026-11-24"
    assert JsonSafe.encode(~T[10:15:00]) == "10:15:00"
    assert JsonSafe.encode(~N[2026-11-24 10:15:00]) == "2026-11-24T10:15:00"
    assert JsonSafe.encode(~U[2026-11-24 10:15:00Z]) == "2026-11-24T10:15:00Z"
  end

  test "atom values become their names while true, false and nil stay" do
    assert JsonSafe.encode(%{verdict: :weak, done: true, failed: false, error: nil}) ==
             %{verdict: "weak", done: true, failed: false, error: nil}
  end

  test "nested maps and lists are walked and their keys kept" do
    value = %{"rows" => [%{cpc: Decimal.new("1.25"), trend: [%{month: 10, search_volume: 300}]}], fetched: ~D[2026-11-01]}

    assert JsonSafe.encode(value) == %{
             "rows" => [%{cpc: "1.25", trend: [%{month: 10, search_volume: 300}]}],
             fetched: "2026-11-01"
           }
  end

  test "strings, numbers and floats are kept as they are" do
    assert JsonSafe.encode(["fraza", 12, 0.25]) == ["fraza", 12, 0.25]
  end

  test "a struct without a JSON form raises" do
    assert_raise ArgumentError, ~r/URI has no JSON form/, fn ->
      JsonSafe.encode(%{"site" => URI.parse("https://example.com")})
    end
  end
end
