defmodule Dirmoon.Niches.NicheTest do
  use ExUnit.Case, async: true

  alias Dirmoon.Niches.Niche

  test "the Niche statuses are the values its status column accepts" do
    assert Niche.statuses() == Ecto.Enum.values(Niche, :status)
  end
end
