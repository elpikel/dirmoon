defmodule Dirmoon.Workers.FilterAndGroupLimitTest do
  use Dirmoon.DataCase, async: false
  use Oban.Testing, repo: Dirmoon.Repo

  import Mox

  alias Dirmoon.Phrases.RunPhrase
  alias Dirmoon.Workers.FilterAndGroup

  test "phrases beyond the analysis limit are not sent and are rejected as outside the limit" do
    previous_limit = Application.fetch_env!(:dirmoon, :grouping_phrase_limit)
    Application.put_env(:dirmoon, :grouping_phrase_limit, 2)
    on_exit(fn -> Application.put_env(:dirmoon, :grouping_phrase_limit, previous_limit) end)

    run = insert(:run, steps: build_run_steps())
    top = phrase_in_run(run, "hotel dla psów", 300)
    second = phrase_in_run(run, "hotel dla psa cena", 200)
    beyond = phrase_in_run(run, "psi hotel opinie", 5)
    test_process = self()

    expect(Dirmoon.LLMMock, :structured, 1, fn %{input: %{phrases: phrases}} ->
      send(test_process, {:sent_ids, Enum.map(phrases, & &1.id)})
      answer(%{"niches" => [niche_answer("Hotel dla psa", [top.id, second.id, beyond.id])], "rejected" => []})
    end)

    :ok = perform_job(FilterAndGroup, %{run_id: run.id})

    assert_received {:sent_ids, [top_id, second_id]}
    assert [top_id, second_id] == [top.id, second.id]

    assert %RunPhrase{status: :rejected, rejection_reason: "poza limitem analizy", cluster_id: nil} =
             Repo.get!(RunPhrase, beyond.id)
  end

  defp phrase_in_run(run, text, search_volume) do
    phrase = insert(:phrase, phrase: unique_phrase_text(text))
    insert(:metrics, phrase: phrase, location_code: run.location_code, search_volume: search_volume)
    insert(:run_phrase, run: run, phrase: phrase)
  end

  defp niche_answer(name, phrase_ids) do
    %{
      "name" => name,
      "intent" => "transakcyjna",
      "reading" => "Ludzie szukają tej usługi. Odpowiadają im katalogi.",
      "phrase_ids" => phrase_ids
    }
  end

  defp answer(body), do: {:ok, body, Decimal.new("0.004")}
end
