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

  test "the dark how it works panel sums up the nine Steps in four Step Groups", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    panel = LazyHTML.query(document, "#how-it-works[data-surface=dark]")

    assert panel |> LazyHTML.query("[data-part=context]") |> squish() == "dirmoon / jak to działa"

    step_group_names = panel |> LazyHTML.query("[data-part=step-group-name]") |> Enum.map(&squish/1)
    step_group_steps = panel |> LazyHTML.query("[data-part=step-group-steps]") |> Enum.map(&squish/1)

    assert step_group_names == ["Frazy", "Popyt", "Konkurencja", "Strona"]
    assert step_group_steps == ["01–02", "03–04", "05–07", "08–09"]
  end

  test "a signed-out visitor is offered sign-in in the nav", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("#landing-nav a[href='/users/log-in']") |> squish() == "Zaloguj się"
    assert document |> LazyHTML.query("#landing-nav a[href='/app']") |> Enum.count() == 0
  end

  test "a signed-in user opening the landing page is redirected to the app", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})

    conn = get(conn, ~p"/")

    assert redirected_to(conn) == ~p"/app"
  end

  test "after logging out the landing page shows the log-out notice with a close button", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})

    conn = delete(conn, ~p"/users/log-out")

    document = conn |> recycle() |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    notice = LazyHTML.query(document, "#flash-group #flash-info[role=alert]")

    assert squish(notice) =~ "Wylogowano."
    assert [close_command] = LazyHTML.attribute(notice, "phx-click")
    assert close_command =~ "#flash-info"
    assert notice |> LazyHTML.query("button[type=button][aria-label]") |> Enum.count() == 1
  end

  defp squish(node) do
    node |> LazyHTML.text() |> String.split() |> Enum.join(" ")
  end
end
