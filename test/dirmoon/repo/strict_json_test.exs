defmodule Dirmoon.Repo.StrictJsonTest do
  use Dirmoon.DataCase, async: true

  alias Dirmoon.Repo.StrictJson

  test "a decimal nested anywhere in a value is refused" do
    for value <- [
          Decimal.new("0.66"),
          %{"cpc" => Decimal.new("0.66")},
          %{"items" => [%{"cpc" => Decimal.new("0.66")}]},
          [1, [Decimal.new("0.66")]]
        ] do
      assert_raise ArgumentError, ~r/Decimal 0.66 in a jsonb value/, fn -> StrictJson.encode_to_iodata!(value) end
    end
  end

  test "values without a decimal, calendar structs included, are encoded as Jason does" do
    value = %{"cpc" => 0.66, "fetched_at" => ~U[2026-11-24 10:00:00Z], "items" => [1, "dwa", nil, true]}

    assert value |> StrictJson.encode_to_iodata!() |> IO.iodata_to_binary() |> Jason.decode!() == %{
             "cpc" => 0.66,
             "fetched_at" => "2026-11-24T10:00:00Z",
             "items" => [1, "dwa", nil, true]
           }
  end

  test "JSON text is decoded" do
    assert StrictJson.decode!(~s({"cpc": "0.66"})) == %{"cpc" => "0.66"}
  end

  test "the Repo refuses to write a decimal into a jsonb column in every build" do
    run = insert(:run)
    api_request = build(:api_request, run: run, response: %{"cpc" => Decimal.new("0.66")})

    assert_raise ArgumentError, ~r/Decimal 0.66 in a jsonb value/, fn -> Repo.insert!(api_request) end
  end
end
