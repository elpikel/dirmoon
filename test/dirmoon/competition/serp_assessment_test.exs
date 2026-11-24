defmodule Dirmoon.Competition.SerpAssessmentTest do
  use ExUnit.Case, async: true

  alias Dirmoon.Competition.SerpAssessment

  test "the direct competitor is one of the Page Types" do
    assert SerpAssessment.direct_competitor() == :direct_competitor
    assert SerpAssessment.direct_competitor() in SerpAssessment.page_types()
  end

  test "the weak Page Types are blogs, forums and directories, never a direct competitor" do
    assert Enum.sort(SerpAssessment.weak_page_types()) == [:blog, :directory, :forum]
    assert Enum.all?(SerpAssessment.weak_page_types(), &(&1 in SerpAssessment.page_types()))
    refute SerpAssessment.direct_competitor() in SerpAssessment.weak_page_types()
  end
end
