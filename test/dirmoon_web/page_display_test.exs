defmodule DirmoonWeb.PageDisplayTest do
  use Dirmoon.DataCase, async: true

  alias Dirmoon.Pages.Page
  alias DirmoonWeb.PageDisplay

  test "every page status has a label" do
    for status <- Page.statuses() do
      assert is_binary(PageDisplay.status_label(status))
    end
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
end
