defmodule DirmoonWeb.LayoutsTest do
  use DirmoonWeb.ConnCase, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias DirmoonWeb.Layouts

  test "the app layout puts the content on the dotted page inside the 1180px column" do
    assigns = %{}

    document = parse(~H|<Layouts.app flash={%{}}>
  <p id="content">Treść</p>
</Layouts.app>|)

    assert has_class?(document, "[data-layout=app]", "page-dots")
    assert has_class?(document, "main", "max-w-content")
    assert has_class?(document, "main", "sm:px-gutter")
    assert has_class?(document, "main", "px-gutter-phone")
    assert document |> LazyHTML.query("main #content") |> Enum.count() == 1
    assert document |> LazyHTML.query("#flash-group") |> Enum.count() == 1
  end

  test "the app nav card links to results, pages and a dark new research button" do
    assigns = %{}

    document = parse(~H|<Layouts.app flash={%{}}>Treść</Layouts.app>|)

    assert document |> LazyHTML.query("#app-nav [data-part=brand]") |> Enum.count() == 1
    assert link_text(document, "#app-nav nav a[href='/app/runs']") == "Wyniki"
    assert link_text(document, "#app-nav nav a[href='/app/pages']") == "Strony"
    assert link_text(document, "#app-nav nav a[href='/app/research/new'][data-variant=dark]") == "Nowy research"
    assert document |> LazyHTML.query("#app-nav [aria-current]") |> Enum.count() == 0
  end

  test "the app layout shows the DANE TESTOWE banner when demo data is on" do
    assigns = %{}

    document = parse(~H|<Layouts.app flash={%{}} demo_data>Treść</Layouts.app>|)

    banner_text = link_text(document, "#demo-data-banner")
    assert banner_text =~ "DANE TESTOWE"
    assert banner_text =~ "Aplikacja używa danych demonstracyjnych, nie prawdziwych wyników"
  end

  test "the app layout has no DANE TESTOWE banner when demo data is off" do
    assigns = %{}

    document = parse(~H|<Layouts.app flash={%{}} demo_data={false}>Treść</Layouts.app>|)

    assert document |> LazyHTML.query("#demo-data-banner") |> Enum.count() == 0
  end

  test "the app nav card marks the active link as the current page" do
    assigns = %{}

    document = parse(~H|<Layouts.app flash={%{}} active={:pages}>Treść</Layouts.app>|)

    assert ["page"] = document |> LazyHTML.query("#app-nav a[href='/app/pages']") |> LazyHTML.attribute("aria-current")
    assert document |> LazyHTML.query("#app-nav a[href='/app/runs'][aria-current]") |> Enum.count() == 0
  end

  test "the landing layout shows the nav card with the caller's right-hand side" do
    assigns = %{}

    document =
      parse(~H"""
      <Layouts.landing flash={%{}}>
        <:nav><a id="sign-in" href="/users/log-in">Zaloguj się</a></:nav>
        <section id="hero">Hero</section>
      </Layouts.landing>
      """)

    assert has_class?(document, "[data-layout=landing]", "page-dots")
    assert document |> LazyHTML.query("#landing-nav nav #sign-in") |> Enum.count() == 1
    assert document |> LazyHTML.query("#landing-nav a[href='/app/runs']") |> Enum.count() == 0
    assert document |> LazyHTML.query("main #hero") |> Enum.count() == 1
  end

  test "the auth layout centres a card under the mark on the dotted page" do
    assigns = %{}

    document = parse(~H|<Layouts.auth flash={%{}}>
  <h1 id="title">Zaloguj się</h1>
</Layouts.auth>|)

    assert has_class?(document, "[data-layout=auth]", "page-dots")
    assert document |> LazyHTML.query("[data-layout=auth] a[href='/'] svg[data-moon-mark]") |> Enum.count() == 1
    assert has_class?(document, "main", "bg-white")
    assert document |> LazyHTML.query("main #title") |> Enum.count() == 1
  end

  test "pages are served in Polish with the dirmoon title and no theme toggle script", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert ["pl"] = document |> LazyHTML.query("html") |> LazyHTML.attribute("lang")
    assert document |> LazyHTML.query("title") |> LazyHTML.text() |> String.trim() =~ ~r/ · dirmoon$/
    refute document |> LazyHTML.query("script") |> LazyHTML.text() =~ "phx:theme"
  end

  test "fonts are served from the app, never from Google Fonts", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)
    fonts_css = File.read!("assets/css/fonts.css")

    refute html =~ "fonts.googleapis"
    refute html =~ "fonts.gstatic"
    refute fonts_css =~ "googleapis"
    refute fonts_css =~ "gstatic"

    font_urls = ~r{url\((/fonts/[\w.-]+\.woff2)\)} |> Regex.scan(fonts_css, capture: :all_but_first) |> List.flatten()

    for family <- ["inter-latin", "inter-latin-ext", "jetbrains-mono-latin", "jetbrains-mono-latin-ext"] do
      assert Enum.any?(font_urls, &String.starts_with?(&1, "/fonts/#{family}-")), "#{family} missing"
    end

    for weight <- ~w(400 500 600 700 800) do
      assert "/fonts/inter-latin-ext-#{weight}-normal.woff2" in font_urls
    end

    for url <- font_urls do
      assert File.exists?(Path.join("priv/static", url)), "#{url} is not in priv/static"
    end

    assert "fonts" in DirmoonWeb.static_paths()
  end

  test "font files are served by the endpoint", %{conn: conn} do
    conn = get(conn, "/fonts/inter-latin-ext-800-normal.woff2")

    assert conn.status == 200
  end

  defp parse(rendered) do
    rendered |> rendered_to_string() |> LazyHTML.from_fragment()
  end

  defp has_class?(document, selector, class) do
    document
    |> LazyHTML.query(selector)
    |> LazyHTML.attribute("class")
    |> Enum.any?(fn classes -> class in String.split(classes || "") end)
  end

  defp link_text(document, selector) do
    document |> LazyHTML.query(selector) |> LazyHTML.text() |> String.split() |> Enum.join(" ")
  end
end
