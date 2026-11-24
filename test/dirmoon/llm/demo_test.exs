defmodule Dirmoon.LLM.DemoTest do
  use ExUnit.Case, async: true

  alias Dirmoon.LLM.Demo
  alias Dirmoon.Pages.Brief
  alias Dirmoon.Pages.Placeholders
  alias Dirmoon.Pages.Template

  test "seeds are twelve lowercase phrases from the description with city variants, plus six questions" do
    input = %{description: "Hotel dla Psów i opieka nad kotami", city: "Gdańsk", priority_services: ["Strzyżenie psów"]}

    assert {:ok, %{"seeds" => seeds, "questions" => questions}, cost} = Demo.structured(request(:seeds, input))

    assert Enum.count(seeds) == 12
    assert seeds == Enum.uniq(seeds)
    assert Enum.all?(seeds, &(&1 == String.downcase(&1)))
    assert "hotel" in seeds
    assert "hotel gdańsk" in seeds
    assert Enum.count(questions) == 6
    assert Enum.all?(questions, &(String.starts_with?(&1, Dirmoon.demo_marker()) and String.ends_with?(&1, "?")))
    assert Decimal.equal?(cost, 0)
  end

  test "seeds without a city have no city variants and still number twelve" do
    input = %{description: "Hotel dla psów", city: nil, priority_services: nil}

    assert {:ok, %{"seeds" => seeds}, _cost} = Demo.structured(request(:seeds, input))

    assert Enum.count(seeds) == 12
    assert seeds == Enum.uniq(seeds)
    assert "hotel" in seeds
  end

  test "filter and group splits the given phrase ids into at most four niches and rejects every seventh" do
    phrases = for number <- 1..15, do: %{id: number * 11, phrase: "fraza #{number}", volume: number}

    assert {:ok, %{"niches" => niches, "rejected" => rejected}, cost} =
             Demo.structured(request(:filter_and_group, %{phrases: phrases}))

    assert Enum.count(niches) == 4
    assert Enum.map(rejected, & &1["phrase_id"]) == [77, 154]
    assert Enum.all?(rejected, &(&1["reason"] == "(demo) poza ofertą"))

    grouped_ids = Enum.flat_map(niches, & &1["phrase_ids"])
    assert Enum.sort(grouped_ids ++ [77, 154]) == Enum.map(phrases, & &1.id)

    assert Enum.all?(niches, fn niche ->
             String.starts_with?(niche["name"], Dirmoon.demo_marker()) and is_binary(niche["intent"]) and
               String.starts_with?(niche["reading"], Dirmoon.demo_marker()) and niche["phrase_ids"] != []
           end)

    assert Decimal.equal?(cost, 0)
  end

  test "filter and group with no phrases returns no niches" do
    assert {:ok, %{"niches" => [], "rejected" => []}, _cost} =
             Demo.structured(request(:filter_and_group, %{phrases: []}))
  end

  test "label serp gives every result a known page type, the same one for the same domain" do
    results = [
      %{position: 1, url: "https://psi-hotel.example/", domain: "psi-hotel.example", title: "Psi hotel"},
      %{position: 2, url: "https://forum.example/watek", domain: "forum.example", title: "Wątek"},
      %{position: 3, url: "https://psi-hotel.example/cennik", domain: "psi-hotel.example", title: "Cennik"}
    ]

    assert {:ok, %{"labels" => labels}, cost} =
             Demo.structured(request(:label_serp, %{phrase: "hotel dla psów", results: results}))

    assert Enum.map(labels, & &1["position"]) == [1, 2, 3]
    assert Enum.all?(labels, &(&1["page_type"] in ~w(direct_competitor directory forum portal blog)))
    assert Enum.at(labels, 0)["page_type"] == Enum.at(labels, 2)["page_type"]
    assert Decimal.equal?(cost, 0)
  end

  test "the brief is visibly synthetic, uses the given phrases and keeps Fact Tiles as placeholders" do
    input = %{
      niche_name: "Hotel dla psów",
      phrases: ["hotel dla psów gdańsk", "hotel dla psa", "opieka nad psem"],
      questions: ["Czy pies może mieszkać z innymi psami?"],
      business_description: "Hotel dla psów z wybiegiem",
      city: "Gdańsk"
    }

    assert {:ok, brief, cost} = Demo.structured(request(:brief, input))

    assert brief["primary_phrase"] == "hotel dla psów gdańsk"
    assert brief["phrases"] != []
    assert Enum.all?(brief["phrases"], &(&1 in input.phrases))
    assert brief["business_name"] == "[NAZWA FIRMY]"
    assert brief["slug"] =~ ~r/\A[a-z0-9]+(-[a-z0-9]+)*\z/
    assert String.starts_with?(brief["title"], Dirmoon.demo_marker())
    assert String.starts_with?(brief["h1"], Dirmoon.demo_marker())
    assert String.starts_with?(brief["intro"], Dirmoon.demo_marker())
    assert String.starts_with?(brief["short_answer"], Dirmoon.demo_marker())
    assert is_binary(brief["breadcrumb"]) and is_binary(brief["cta_label"])

    assert Enum.count(brief["fact_tiles"]) == 3
    assert Enum.all?(brief["fact_tiles"], &(is_binary(&1["label"]) and &1["value"] =~ ~r/\A\[[^\]]+\]\z/))

    assert Enum.count(brief["sections"]) == 4
    assert hd(brief["sections"])["question"] == "Czy pies może mieszkać z innymi psami?"

    assert Enum.all?(
             brief["sections"],
             &(String.ends_with?(&1["question"], "?") and String.starts_with?(&1["answer"], Dirmoon.demo_marker()))
           )

    assert Decimal.equal?(cost, 0)
  end

  test "the brief never contains a phone number, price, e-mail or address" do
    input = %{
      niche_name: "Hotel dla psów",
      phrases: ["hotel dla psów"],
      questions: [],
      business_description: "Hotel dla psów, ul. Długa 5, tel. 600 100 200, biuro@psy.example, od 80 zł",
      city: nil
    }

    assert {:ok, brief, _cost} = Demo.structured(request(:brief, input))

    text = brief |> Map.values() |> Jason.encode!()
    refute text =~ input.business_description
    refute text =~ "Długa 5"
    refute text =~ "600 100 200"
    refute text =~ "biuro@psy.example"
    refute text =~ "80 zł"
    refute text =~ ~r/\d/
    refute text =~ "@"
    refute text =~ ~r/zł|pln|ul\./i
  end

  test "an unknown task is an error" do
    assert Demo.structured(request(:poem, %{})) == {:error, {:unknown_llm_task, :poem}}
  end

  test "the demo marker is not a Placeholder" do
    refute Placeholders.placeholder?(Dirmoon.demo_marker())
    assert (Dirmoon.demo_marker() <> " Ile kosztuje hotel?") |> Placeholders.split() |> Enum.all?(&(not &1.placeholder))
  end

  test "a page from the demo brief shows the demo marker as text and never as a placeholder pill" do
    input = %{
      niche_name: "#{Dirmoon.demo_marker()} Nisza: hotel dla psów",
      phrases: ["hotel dla psów gdańsk"],
      questions: ["#{Dirmoon.demo_marker()} Ile kosztuje hotel?"],
      business_description: "Hotel dla psów",
      city: "Gdańsk"
    }

    {:ok, brief_params, _cost} = Demo.structured(request(:brief, input))

    document =
      %Brief{}
      |> Brief.changeset(brief_params)
      |> Ecto.Changeset.apply_action!(:insert)
      |> Template.render(%{mode: :new_idea})
      |> LazyHTML.from_document()

    placeholder_texts = document |> LazyHTML.query("span.placeholder") |> Enum.map(&LazyHTML.text/1)

    assert "[NAZWA FIRMY]" in placeholder_texts
    refute Enum.any?(placeholder_texts, &String.contains?(&1, "demo"))
    assert document |> LazyHTML.query("h1") |> LazyHTML.text() =~ Dirmoon.demo_marker()
  end

  defp request(task, input) do
    %{task: task, system: "System", prompt: "Prompt", schema: %{"type" => "object"}, input: input}
  end
end
