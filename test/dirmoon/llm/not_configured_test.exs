defmodule Dirmoon.LLM.NotConfiguredTest do
  use ExUnit.Case, async: true

  alias Dirmoon.LLM.NotConfigured

  test "every request fails because no LLM provider is configured" do
    for task <- Dirmoon.LLM.tasks() do
      assert NotConfigured.structured(%{task: task, system: "", prompt: "", schema: %{}, input: %{}}) ==
               {:error, :llm_not_configured}
    end
  end
end
