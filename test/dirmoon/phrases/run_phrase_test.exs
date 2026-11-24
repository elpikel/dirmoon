defmodule Dirmoon.Phrases.RunPhraseTest do
  use ExUnit.Case, async: true

  alias Dirmoon.Phrases.RunPhrase

  test "a run keeps or rejects each of its Phrases" do
    assert RunPhrase.statuses() == Ecto.Enum.values(RunPhrase, :status)
    assert RunPhrase.statuses() == [:kept, :rejected]
  end
end
