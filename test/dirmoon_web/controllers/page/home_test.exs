defmodule DirmoonWeb.Controllers.Page.HomeTest do
  use DirmoonWeb.ConnCase, async: true

  test "a signed-out visitor sees the landing page on the dotted page with the nav card", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("[data-layout=landing].page-dots") |> Enum.count() == 1
    assert document |> LazyHTML.query("#landing-nav [data-part=brand]") |> Enum.count() == 1
  end

  test "the hero headline asks to check whether anyone searches before building, with the lime underline",
       %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    headline = LazyHTML.query(document, "#landing-hero h1")

    assert squish(headline) == "Before you build it, check if anyone searches for it."

    assert headline |> LazyHTML.query("[data-part=underline] svg[data-part=stroke] path.stroke-accent") |> Enum.count() ==
             1

    assert headline |> LazyHTML.query("[data-part=underline] svg[data-part=rocket]") |> Enum.count() == 1
  end

  test "the hero sign-up form has a labelled email input and a Create account button", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    form = LazyHTML.query(document, "#landing-hero form#sign-up-form-hero[action='/sign-up'][method=post]")
    [email_input_id] = form |> LazyHTML.query("input[type=email][name='user[email]']") |> LazyHTML.attribute("id")

    assert form |> LazyHTML.query("label.sr-only[for='#{email_input_id}']") |> squish() != ""
    assert form |> LazyHTML.query("button[type=submit]") |> squish() == "Create account"
  end

  test "the closing band has a second sign-up form", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    form = LazyHTML.query(document, "form#sign-up-form-closing[action='/sign-up']")
    [email_input_id] = form |> LazyHTML.query("input[type=email][name='user[email]']") |> LazyHTML.attribute("id")

    assert form |> LazyHTML.query("label.sr-only[for='#{email_input_id}']") |> squish() != ""
    assert form |> LazyHTML.query("button[type=submit]") |> squish() == "Create account"
  end

  test "the page is in English, with an English title", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("html") |> LazyHTML.attribute("lang") == ["en"]
    assert document |> LazyHTML.query("title") |> squish() == "Check demand before you build · dirmoon"
  end

  test "the journey walks four steps from the idea to the decision, along a flight path with the rocket",
       %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    journey = LazyHTML.query(document, "#journey #journey-steps")

    assert journey |> LazyHTML.query("[data-part=flight-path][aria-hidden=true] svg[data-rocket]") |> Enum.count() == 1

    assert journey |> LazyHTML.query("[data-part=step]") |> LazyHTML.attribute("id") ==
             ~w(journey-steps-idea journey-steps-research journey-steps-report journey-steps-value)

    assert journey |> LazyHTML.query("[data-part=step] [data-part=number]") |> Enum.map(&squish/1) == ~w(01 02 03 04)

    assert journey |> LazyHTML.query("[data-part=step] h3") |> Enum.map(&squish/1) == [
             "You start with a question",
             "dirmoon checks real search data",
             "You get a ranked report",
             "You decide with numbers, not hope"
           ]

    assert document |> LazyHTML.query("#how-it-works") |> Enum.count() == 0
  end

  test "the journey's example is one real research: what was typed, what it cost and the ranked Niches",
       %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("#journey-steps-idea [data-part=description]") |> squish() == "“Ice skate rental”"
    assert document |> LazyHTML.query("#journey input, #journey [class*=shadow-prompt]") |> Enum.count() == 0

    questions = [
      "Do people search for this at all, and how many of them?",
      "Is a customer here worth real money?",
      "Who is already there, and can I get past them?",
      "What do my competitors charge?"
    ]

    assert document |> LazyHTML.query("#journey-steps-idea [data-part=questions] li") |> Enum.map(&squish/1) == questions

    assert document |> LazyHTML.query("#journey-steps-idea [data-part=city]") |> squish() == "Gdańsk, Poland"

    assert document |> LazyHTML.query("#journey-steps-sources dt") |> Enum.map(&squish/1) == [
             "Where do the numbers come from?",
             "Does an AI make any of it up?"
           ]

    sources = document |> LazyHTML.query("#journey-steps-sources dd") |> Enum.map(&squish/1)

    assert Enum.at(sources, 0) =~ "Google's own keyword and search results data"
    assert Enum.at(sources, 1) =~ "never from an AI's guess"
    refute document |> LazyHTML.query("#journey") |> squish() =~ "API fees"

    report = LazyHTML.query(document, "#journey-steps-report")
    panel = LazyHTML.query(report, "#journey-steps-report-panel[data-surface=dark]")

    assert panel |> LazyHTML.query("[data-part=context]") |> squish() == "dirmoon / ice skate rental"
    assert panel |> LazyHTML.query("[data-part=note]") |> squish() == "7 niches"

    niches = LazyHTML.query(panel, "[data-part=niche]")

    assert niches |> LazyHTML.query("[data-part=name]") |> Enum.map(&squish/1) ==
             ["Skate rental", "Ice rinks with skate rental", "Skates for kids"]

    assert niches |> LazyHTML.query("[data-part=verdict]") |> Enum.map(&squish/1) ==
             ["Worth it, but hard · 7.7/10", "Worth it, but hard · 5.6/10", "Probably not worth it · 2.3/10"]

    assert niches |> LazyHTML.query("[data-part=figures]") |> Enum.at(0) |> squish() ==
             "1,090 searches a month · $6.79 per ad click"

    assert panel |> LazyHTML.query("[data-part=more]") |> squish() =~ "And 4 more niches"
    assert report |> LazyHTML.query("figcaption") |> squish() =~ "A real research from 24 Nov 2026"

    assert report |> LazyHTML.query("#journey-steps-answers dt") |> Enum.map(&squish/1) == questions

    answers = report |> LazyHTML.query("#journey-steps-answers dd") |> Enum.map(&squish/1)

    assert Enum.at(answers, 0) =~ "1,090 searches a month"
    assert Enum.at(answers, 1) =~ "$6.79"
    assert Enum.at(answers, 2) =~ "with a link to each"
    assert Enum.at(answers, 3) =~ "lists the prices they publish"

    value = document |> LazyHTML.query("#journey-steps-value") |> squish()

    assert value =~ "5 of 7 niches turned out not worth a page"

    assert value =~
             "dirmoon writes its brief: the plan and the text for one page about that niche, with the title, headings, sections and the phrases to cover. You hand it to whoever builds your site."

    refute value =~ "page content"
  end

  test "a signed-out visitor is offered sign-in in the nav", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("#landing-nav a#sign-in-link[data-variant=dark][href='/users/log-in']") |> squish() ==
             "Sign in"

    assert document |> LazyHTML.query("#landing-nav a[href='/app']") |> Enum.count() == 0
  end

  test "a signed-in user opening the landing page is redirected to the app", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})

    conn = get(conn, ~p"/")

    assert redirected_to(conn) == ~p"/app"
  end

  test "after logging out the landing page shows no notice", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})

    conn = delete(conn, ~p"/users/log-out")

    document = conn |> recycle() |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("#flash-group, [role=alert]") |> Enum.count() == 0
  end

  defp squish(node) do
    node |> LazyHTML.text() |> String.split() |> Enum.join(" ")
  end
end
