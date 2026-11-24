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

    assert squish(headline) == "Zanim zbudujesz, sprawdź, czy ktoś tego szuka."
    assert headline |> LazyHTML.query("[data-part=underline] svg path.stroke-accent") |> Enum.count() == 1
  end

  test "the hero sign-up form has a labelled email input and a Załóż konto button", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    form = LazyHTML.query(document, "#landing-hero form#sign-up-form-hero[action='/sign-up'][method=post]")
    [email_input_id] = form |> LazyHTML.query("input[type=email][name='user[email]']") |> LazyHTML.attribute("id")

    assert form |> LazyHTML.query("label.sr-only[for='#{email_input_id}']") |> squish() != ""
    assert form |> LazyHTML.query("button[type=submit]") |> squish() == "Załóż konto"
  end

  test "the closing band has a second sign-up form", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    form = LazyHTML.query(document, "form#sign-up-form-closing[action='/sign-up']")
    [email_input_id] = form |> LazyHTML.query("input[type=email][name='user[email]']") |> LazyHTML.attribute("id")

    assert form |> LazyHTML.query("label.sr-only[for='#{email_input_id}']") |> squish() != ""
    assert form |> LazyHTML.query("button[type=submit]") |> squish() == "Załóż konto"
  end

  test "the dark how it works panel sums up the nine steps in four stages", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    panel = LazyHTML.query(document, "#how-it-works[data-surface=dark]")

    assert panel |> LazyHTML.query("[data-part=context]") |> squish() == "dirmoon / jak to działa"

    stage_names = panel |> LazyHTML.query("[data-part=stage-name]") |> Enum.map(&squish/1)
    stage_steps = panel |> LazyHTML.query("[data-part=stage-steps]") |> Enum.map(&squish/1)

    assert stage_names == ["Frazy", "Popyt", "Konkurencja", "Strona"]
    assert stage_steps == ["01–02", "03–04", "05–07", "08–09"]
  end

  test "a signed-out visitor is offered sign-in in the nav", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("#landing-nav a[href='/users/log-in']") |> squish() == "Zaloguj się"
    assert document |> LazyHTML.query("#landing-nav a[href='/app']") |> Enum.count() == 0
  end

  test "a signed-in user is offered the app instead of sign-in in the nav", %{conn: conn} do
    user = insert(:user)

    document =
      conn
      |> log_in_user(user)
      |> get(~p"/")
      |> html_response(200)
      |> LazyHTML.from_document()

    assert document |> LazyHTML.query("#landing-nav a[href='/app']") |> squish() == "Przejdź do aplikacji"
    assert document |> LazyHTML.query("#landing-nav a[href='/users/log-in']") |> Enum.count() == 0
  end

  defp squish(node) do
    node |> LazyHTML.text() |> String.split() |> Enum.join(" ")
  end
end
