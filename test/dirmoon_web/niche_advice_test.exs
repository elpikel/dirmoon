defmodule DirmoonWeb.NicheAdviceTest do
  use ExUnit.Case, async: true

  alias Dirmoon.Niches.Niche
  alias DirmoonWeb.NicheAdvice

  test "a Niche scoring 4 or more without strong competition is worth trying, in the accent" do
    advice =
      NicheAdvice.advice(
        summary(%{score: "4.0", competition: %{verdict: :medium, holders: "big portals, businesses like yours"}})
      )

    assert %{kind: :worth, label: "Worth a try", class: "text-accent"} = advice

    assert advice.competition ==
             "Medium competition: Google's first page is a mix of big portals, businesses like yours. Getting onto it is possible, but not at once."
  end

  test "a Niche scoring 4 or more against strong competition is worth it but hard, in the warning colour" do
    advice =
      NicheAdvice.advice(
        summary(%{score: "8.1", competition: %{verdict: :strong, holders: "businesses like yours, big portals"}})
      )

    assert %{kind: :hard, label: "Worth it, but hard", class: "text-warn"} = advice

    assert advice.competition ==
             "Strong competition: Google's first page today holds mostly businesses like yours, big portals. Getting onto it will be hard and slow."
  end

  test "a Niche scoring under 4 is rather not worth it, whatever its competition" do
    advice =
      NicheAdvice.advice(
        summary(%{score: "3.9", competition: %{verdict: :weak, holders: "business directories, big portals"}})
      )

    assert %{kind: :low, label: "Probably not worth it", class: "text-on-app-muted"} = advice

    assert advice.competition ==
             "Weak competition: Google's first page today holds mostly business directories, big portals, not offers from businesses like yours. A good page can get onto it."
  end

  test "an unscored Niche has no verdict" do
    assert %{kind: :unscored, label: "Not rated yet", class: "text-on-app-muted"} =
             NicheAdvice.advice(summary(%{score: nil}))
  end

  test "the demand reason gives the monthly searches, or says nobody searches" do
    assert NicheAdvice.advice(summary(%{volume: 1_090})).demand ==
             "People type these searches into Google about 1,090 times a month."

    assert NicheAdvice.advice(summary(%{volume: 1})).demand ==
             "People type these searches into Google about 1 time a month."

    assert NicheAdvice.advice(summary(%{volume: 0})).demand ==
             "Almost nobody types these into Google: Google can't measure even one search a month."
  end

  test "the value reason gives the price of a click, or says nobody advertises" do
    assert NicheAdvice.advice(summary(%{cpc: Decimal.new("6.79")})).value ==
             "Businesses pay Google $6.79 on average for one ad click on these searches. The higher the price, the more a customer is worth."

    assert NicheAdvice.advice(summary(%{cpc: nil})).value ==
             "Nobody pays Google for ads on these searches, so I can't tell what a customer is worth here."
  end

  test "the competition reason says so when no Phrase was checked" do
    assert NicheAdvice.advice(summary(%{competition: nil})).competition ==
             "I haven't checked who is on Google's first page for these searches."
  end

  test "the list figures give how many times a month people type the searches and the competition verdict with what it means" do
    strong = %{verdict: :strong, holders: "businesses like yours"}

    assert NicheAdvice.figures(summary(%{volume: 1_090, competition: strong})) ==
             "Typed 1,090 times a month · strong competition, hard to get onto Google's first page"

    assert NicheAdvice.figures(summary(%{volume: 1, competition: nil})) ==
             "Typed 1 time a month · competition not checked yet"

    assert NicheAdvice.figures(summary(%{volume: 22, competition: %{verdict: :weak, holders: "guides and blogs"}})) ==
             "Typed 22 times a month · weak competition, easy to get onto Google's first page"
  end

  defp summary(attrs) do
    attrs = Map.merge(%{score: "5.0", volume: 100, cpc: Decimal.new("1.00"), competition: nil}, attrs)

    %{
      niche: %Niche{score: attrs.score && Decimal.new(attrs.score)},
      volume: attrs.volume,
      cpc: attrs.cpc,
      competition: attrs.competition
    }
  end
end
