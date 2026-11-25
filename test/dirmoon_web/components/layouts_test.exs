defmodule DirmoonWeb.LayoutsTest do
  use DirmoonWeb.ConnCase, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Dirmoon.Accounts.Scope
  alias DirmoonWeb.Layouts

  test "the app layout is a full-screen dark gray shell, not the dotted page with a nav card" do
    assigns = %{}

    document = parse(~H|<Layouts.app flash={%{}} context="results">
  <p id="content">Content</p>
</Layouts.app>|)

    assert has_class?(document, "[data-layout=app][data-surface=dark]", "bg-app")
    assert has_class?(document, "[data-layout=app]", "text-on-app")
    assert has_class?(document, "[data-layout=app]", "min-h-screen")
    refute has_class?(document, "[data-layout=app]", "page-dots")
    refute has_class?(document, "main", "max-w-content")
    assert document |> LazyHTML.query(".page-dots, #landing-nav, [data-part=top-bar]") |> Enum.count() == 0
    assert document |> LazyHTML.query("main#app-main #content") |> Enum.count() == 1
    assert document |> LazyHTML.query("#flash-group") |> Enum.count() == 1
  end

  test "the top bar shows the moon mark and dirmoon with the screen's context" do
    assigns = %{}

    document = parse(~H|<Layouts.app flash={%{}} context="camper rental">Content</Layouts.app>|)

    assert document |> LazyHTML.query("#app-top-bar a[data-part=brand] svg[data-moon-mark]") |> Enum.count() == 1

    assert document |> LazyHTML.query("#app-top-bar a[data-part=brand]") |> LazyHTML.attribute("href") == [
             "/app/research/new"
           ]

    assert link_text(document, "#app-top-bar") =~ "dirmoon / camper rental"
    assert has_class?(document, "#app-top-bar > div", "font-mono")
  end

  test "the sidebar links to a new research, the results and the briefs" do
    assigns = %{}

    document = parse(~H|<Layouts.app flash={%{}} context="results">Content</Layouts.app>|)

    assert link_text(document, "#app-nav a#nav-new-research[href='/app/research/new'][data-variant=action]") ==
             "New research"

    assert link_text(document, "#app-nav a#nav-runs[href='/app/runs']") == "Results"
    assert link_text(document, "#app-nav a#nav-pages[href='/app/pages']") == "Briefs"
    assert document |> LazyHTML.query("#app-nav [aria-current]") |> Enum.count() == 0

    for link <- ~w(#nav-new-research #nav-runs #nav-pages) do
      assert has_class?(document, link, "min-h-target-min")
    end
  end

  test "the sidebar marks the active link as the current page" do
    for {active, id} <- [new_research: "nav-new-research", runs: "nav-runs", pages: "nav-pages"] do
      assigns = %{active: active}
      document = parse(~H|<Layouts.app flash={%{}} context="results" active={@active}>Content</Layouts.app>|)

      assert ["page"] = document |> LazyHTML.query("#app-nav ##{id}") |> LazyHTML.attribute("aria-current")
      assert has_class?(document, "##{id}", "bg-app-selected")
      assert document |> LazyHTML.query("#app-nav [aria-current]") |> Enum.count() == 1
    end
  end

  test "on phones the sidebar becomes a row of links under the top bar" do
    assigns = %{}

    document = parse(~H|<Layouts.app flash={%{}} context="results">Content</Layouts.app>|)

    assert has_class?(document, "#app-nav", "flex-wrap")
    assert has_class?(document, "#app-nav", "min-[860px]:flex-col")
    assert has_class?(document, "#app-nav", "min-[860px]:w-[220px]")
    assert has_class?(document, "#app-nav", "max-[859px]:border-b")
  end

  test "the status row shows the moon mark, the screen's sentence and its note" do
    assigns = %{}

    document =
      parse(~H"""
      <Layouts.app flash={%{}} context="results" note="3 researche">
        <:status><span id="sentence">Masz 3 researche.</span></:status>
        Content
      </Layouts.app>
      """)

    assert ["status"] = document |> LazyHTML.query("#app-status") |> LazyHTML.attribute("role")
    assert document |> LazyHTML.query("#app-status svg[data-moon-mark]") |> Enum.count() == 1
    assert link_text(document, "#app-status #sentence") == "Masz 3 researche."
    assert link_text(document, "#app-status #app-note") == "3 researche"
  end

  test "the chrome is the darkest gray, the working area one step lighter and the status row lighter again" do
    assigns = %{}

    document =
      parse(~H"""
      <Layouts.app flash={%{}} context="results" demo_services={["Search Console"]}>
        <:status>Masz 3 researche.</:status>
        Content
      </Layouts.app>
      """)

    assert has_class?(document, "#app-top-bar", "bg-app-chrome")
    assert has_class?(document, "#app-nav", "bg-app-chrome")
    assert has_class?(document, "#demo-data-banner", "bg-app-chrome")
    assert has_class?(document, "[data-layout=app]", "bg-app")
    assert has_class?(document, "#app-status", "bg-app-raised")
    assert has_class?(document, "#app-top-bar", "border-app-line")
  end

  test "a screen with no status sentence and no note has no status row" do
    assigns = %{}

    document = parse(~H|<Layouts.app flash={%{}} context="results">Content</Layouts.app>|)

    assert document |> LazyHTML.query("#app-status") |> Enum.count() == 0
  end

  test "the app layout shows the TEST DATA strip at the very top when demo data is on" do
    assigns = %{}

    document =
      parse(~H|<Layouts.app
  flash={%{}}
  context="results"
  demo_services={["Google searches and competition (DataForSEO)", "Search Console"]}
>
  Content
</Layouts.app>|)

    banner_text = link_text(document, "[data-layout=app] > #demo-data-banner:first-child")
    assert banner_text =~ "TEST DATA"

    assert link_text(document, "#demo-data-services") ==
             "Demo data instead of real data: Google searches and competition (DataForSEO), Search Console."
  end

  test "the app layout has no TEST DATA strip when no service is on demo data" do
    assigns = %{}

    document = parse(~H|<Layouts.app flash={%{}} context="results" demo_services={[]}>Content</Layouts.app>|)

    assert document |> LazyHTML.query("#demo-data-banner") |> Enum.count() == 0
  end

  test "on phones the email is kept only for screen readers and in a tooltip" do
    user = build(:user)
    assigns = %{scope: Scope.for_user(user, build(:account))}

    document = parse(~H|<Layouts.app flash={%{}} context="results" current_scope={@scope}>Content</Layouts.app>|)

    assert has_class?(document, "#app-top-bar #user-menu #user-email", "max-sm:sr-only")
    assert [user.email] == document |> LazyHTML.query("#user-email") |> LazyHTML.attribute("title")
    assert link_text(document, "#user-email") == user.email
  end

  test "settings and log out sit in the top bar on one row and are at least 44px tall" do
    assigns = %{scope: Scope.for_user(build(:user), build(:account))}

    document = parse(~H|<Layouts.app flash={%{}} context="results" current_scope={@scope}>Content</Layouts.app>|)

    assert has_class?(document, "#user-menu", "flex-nowrap")

    assert document |> LazyHTML.query("#app-top-bar #user-menu > a") |> LazyHTML.attribute("id") == [
             "settings-link",
             "log-out-link"
           ]

    assert document |> LazyHTML.query("#settings-link") |> LazyHTML.attribute("href") == ["/users/settings"]
    assert document |> LazyHTML.query("#log-out-link") |> LazyHTML.attribute("data-method") == ["delete"]

    for link <- ~w(#settings-link #log-out-link) do
      assert has_class?(document, link, "min-h-target-min")
    end
  end

  test "an info flash closes itself and an error flash waits to be closed" do
    assigns = %{}

    document =
      parse(~H|<Layouts.app flash={%{"info" => "Saved", "error" => "Error"}} context="results">
  Content
</Layouts.app>|)

    assert [hook] = document |> LazyHTML.query("#flash-group #flash-info") |> LazyHTML.attribute("phx-hook")
    assert String.ends_with?(hook, "AutoDismissFlash")
    assert document |> LazyHTML.query("#flash-group #flash-error") |> Enum.count() == 1
    assert document |> LazyHTML.query("#flash-error[phx-hook]") |> Enum.count() == 0
  end

  test "in the app the flash group stays at the bottom, clear of the top bar and the status row" do
    assigns = %{}

    document = parse(~H|<Layouts.app flash={%{"info" => "Saved"}} context="results">Content</Layouts.app>|)

    for class <- ~w(fixed bottom-4 inset-x-gutter-phone sm:right-gutter sm:w-96) do
      assert has_class?(document, "#flash-group", class)
    end

    refute has_class?(document, "#flash-group", "lg:top-36")
    refute has_class?(document, "#flash-info", "fixed")
  end

  test "in the app the flash notices are drawn in the app's grays" do
    assigns = %{}

    document =
      parse(~H|<Layouts.app flash={%{"info" => "Saved", "error" => "Error"}} context="results">
  Content
</Layouts.app>|)

    assert has_class?(document, "#flash-info [data-kind=info]", "bg-app-raised")
    assert has_class?(document, "#flash-info [data-kind=info]", "border-app-line-strong")
    assert has_class?(document, "#flash-info [data-kind=info] p", "text-on-app-2")
    assert has_class?(document, "#flash-error [data-kind=error]", "border-warn")
    refute has_class?(document, "#flash-info [data-kind=info]", "bg-white")
  end

  test "on the sign-in pages the flash notices stay white cards" do
    assigns = %{}

    document = parse(~H|<Layouts.auth flash={%{"info" => "Saved"}}>Content</Layouts.auth>|)

    assert has_class?(document, "#flash-info [data-kind=info]", "bg-white")
    assert has_class?(document, "#flash-info [data-kind=info]", "border-line")
    assert has_class?(document, "#flash-info [data-kind=info] p", "text-body")
    refute has_class?(document, "#flash-info [data-kind=info]", "bg-app-raised")
  end

  test "on the sign-in pages the flash group sits on the top right on desktop" do
    assigns = %{}

    document = parse(~H|<Layouts.auth flash={%{"info" => "Saved"}}>Content</Layouts.auth>|)

    for class <- ~w(fixed bottom-4 lg:top-36 lg:bottom-auto) do
      assert has_class?(document, "#flash-group", class)
    end
  end

  test "the landing layout shows the nav card with the caller's right-hand side" do
    assigns = %{}

    document =
      parse(~H"""
      <Layouts.landing>
        <:nav><a id="sign-in" href="/users/log-in">Sign in</a></:nav>
        <section id="hero">Hero</section>
      </Layouts.landing>
      """)

    assert has_class?(document, "[data-layout=landing]", "page-dots")
    assert has_class?(document, "#landing-nav", "rounded-nav")
    assert has_class?(document, "main", "max-w-content")
    assert document |> LazyHTML.query("#app-nav, #app-top-bar") |> Enum.count() == 0
    assert document |> LazyHTML.query("#landing-nav nav #sign-in") |> Enum.count() == 1
    assert document |> LazyHTML.query("#flash-group") |> Enum.count() == 0
    assert document |> LazyHTML.query("#landing-nav a[href='/app/runs']") |> Enum.count() == 0
    assert document |> LazyHTML.query("main #hero") |> Enum.count() == 1
  end

  test "the auth layout centres a card under the mark on the dotted page" do
    assigns = %{}

    document = parse(~H|<Layouts.auth flash={%{}}>
  <h1 id="title">Sign in</h1>
</Layouts.auth>|)

    assert has_class?(document, "[data-layout=auth]", "page-dots")
    assert document |> LazyHTML.query("[data-layout=auth] a[href='/'] svg[data-moon-mark]") |> Enum.count() == 1
    assert has_class?(document, "main", "bg-white")
    assert document |> LazyHTML.query("main #title") |> Enum.count() == 1
  end

  test "pages other than the landing page are served in English with the dirmoon title and no theme toggle script",
       %{conn: conn} do
    document = conn |> get(~p"/users/log-in") |> html_response(200) |> LazyHTML.from_document()

    assert ["en"] = document |> LazyHTML.query("html") |> LazyHTML.attribute("lang")
    assert document |> LazyHTML.query("title") |> LazyHTML.text() |> String.trim() =~ ~r/ · dirmoon$/
    refute document |> LazyHTML.query("script") |> LazyHTML.text() =~ "phx:theme"
  end

  test "signed-in app screens and settings paint the page body the app's gray behind the dark shell", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    insert(:market_country)
    insert(:market_language)

    for path <- [~p"/app/runs", ~p"/app/research/new", ~p"/users/settings"] do
      document = conn |> get(path) |> html_response(200) |> LazyHTML.from_document()

      assert has_class?(document, "body", "bg-app"), "#{path} body is not the app's gray"
      refute has_class?(document, "body", "bg-page")
    end
  end

  test "the landing and sign-in pages keep the light page body", %{conn: conn} do
    for path <- [~p"/", ~p"/users/log-in"] do
      document = conn |> get(path) |> html_response(200) |> LazyHTML.from_document()

      assert has_class?(document, "body", "bg-page"), "#{path} body is not light"
      refute has_class?(document, "body", "bg-app")
    end
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
