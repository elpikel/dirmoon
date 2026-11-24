defmodule DirmoonWeb.PageDisplayTest do
  use Dirmoon.DataCase, async: true

  alias Dirmoon.Pages.Page
  alias DirmoonWeb.PageDisplay

  test "every page status has a label and a headline, whether or not its run is stopped" do
    for status <- Page.statuses(), run_stopped? <- [true, false] do
      assert is_binary(PageDisplay.status_label(status))
      assert %{lead: _lead, underline: _underline} = PageDisplay.headline(%{status: status, run_stopped?: run_stopped?})
    end
  end

  test "work waiting on a stopped run is headlined as waiting" do
    assert PageDisplay.headline(%{status: :writing, run_stopped?: true}) == %{lead: "Brief", underline: "czeka."}
    assert PageDisplay.headline(%{status: :publishing, run_stopped?: true}) == %{lead: "Publikacja", underline: "czeka."}
    assert PageDisplay.headline(%{status: :writing, run_stopped?: false}) == %{lead: "Piszę", underline: "brief."}
    assert PageDisplay.headline(%{status: :publishing, run_stopped?: false}) == %{lead: "Publikuję", underline: "stronę."}
  end

  test "every reason a Niche choice is refused has a message" do
    for reason <- [:not_found, :run_not_ready, :run_busy, :brief_in_progress, :not_choosable] do
      assert is_binary(PageDisplay.choose_error(reason))
    end
  end

  test "a page is called by its Brief's title, else its H1, else its Niche's name" do
    niche = build(:niche)
    titled = build(:page, niche: niche, brief: build(:brief, title: "Tytuł testowy"))
    untitled = build(:page, niche: niche, brief: build(:brief, title: " "))
    writing = build(:page, niche: niche, brief: nil, status: :writing)

    assert PageDisplay.title(titled) == "Tytuł testowy"
    assert PageDisplay.title(untitled) == untitled.brief.h1
    assert PageDisplay.title(writing) == niche.name
  end

  test "an unpublished page's address is its slug after the domain Placeholder" do
    assert PageDisplay.address("strona-testowa") == "[TWOJA-DOMENA]/strona-testowa"
    assert PageDisplay.address(nil) == "[TWOJA-DOMENA]/"
  end
end
