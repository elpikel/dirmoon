defmodule DirmoonWeb.UITest do
  use DirmoonWeb.ConnCase, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias DirmoonWeb.UI

  @crescent_path "M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"
  @underline_path "M4 14 C 120 4, 240 22, 360 12 S 540 6, 596 12"

  @app_surface_tokens %{
    "--app-bg" => "#222326",
    "--app-chrome" => "#1C1D1F",
    "--app-raised" => "#2A2B2F",
    "--app-selected" => "#323338",
    "--app-field" => "#1E1F22",
    "--app-line" => "#36373C",
    "--app-line-strong" => "#4A4B51",
    "--on-app" => "#ECECED",
    "--on-app-2" => "#C2C3C7",
    "--on-app-muted" => "#8D8F95"
  }

  @slate_utility ~r/[a-z]-(?:on-)?slate\b/

  test "the moon mark draws the crescent from the reference as one path" do
    assigns = %{}

    document = parse(~H|<UI.moon_mark tone="accent" size={26} />|)

    assert ["26"] = document |> LazyHTML.query("svg[data-moon-mark]") |> LazyHTML.attribute("width")
    assert [@crescent_path] = document |> LazyHTML.query("svg[data-moon-mark] path") |> LazyHTML.attribute("d")
    assert has_class?(document, "svg[data-moon-mark] path", "fill-accent")
  end

  test "the moon mark is decorative and drawn in ink by default" do
    assigns = %{}

    document = parse(~H"<UI.moon_mark />")

    assert ["true"] = document |> LazyHTML.query("svg") |> LazyHTML.attribute("aria-hidden")
    assert ["24"] = document |> LazyHTML.query("svg") |> LazyHTML.attribute("width")
    assert has_class?(document, "svg path", "fill-ink")
  end

  test "the nav card floats with the mark and wordmark linking home on the left and its links on the right" do
    assigns = %{}

    document =
      parse(~H"""
      <UI.nav_card id="nav">
        <UI.button variant="dark" href="/somewhere">Sign in</UI.button>
      </UI.nav_card>
      """)

    for class <- ~w(bg-page border-line rounded-nav shadow-nav) do
      assert has_class?(document, "#nav", class)
    end

    assert document |> LazyHTML.query("#nav [data-part=brand] svg[data-moon-mark]") |> Enum.count() == 1
    assert document |> LazyHTML.query("#nav [data-part=brand]") |> LazyHTML.text() =~ "dirmoon"
    assert has_class?(document, "#nav [data-part=brand]", "font-extrabold")
    assert has_class?(document, "#nav [data-part=brand]", "text-[21px]")
    assert ["/"] = document |> LazyHTML.query("#nav [data-part=brand]") |> LazyHTML.attribute("href")
    assert ["Main"] = document |> LazyHTML.query("#nav nav") |> LazyHTML.attribute("aria-label")
    assert document |> LazyHTML.query("#nav nav a[href='/somewhere']") |> Enum.count() == 1
  end

  test "the eyebrow tag is a small mono uppercase label on the chip fill" do
    assigns = %{}

    document = parse(~H|<UI.eyebrow>Popyt z Google</UI.eyebrow>|)

    for class <- ~w(font-mono text-xs uppercase tracking-[0.1em] bg-chip rounded-chip) do
      assert has_class?(document, "span", class)
    end

    assert document |> LazyHTML.query("span") |> LazyHTML.text() == "Popyt z Google"
  end

  test "the headline wraps its underline phrase in the lime stroke placed behind the text" do
    assigns = %{}

    document =
      parse(~H"""
      <UI.headline size="hero">
        Research
        <:underline>w toku.</:underline>
      </UI.headline>
      """)

    assert has_class?(document, "h1", "font-extrabold")
    assert has_class?(document, "h1", "isolate")
    assert has_class?(document, "h1", "leading-[0.98]")
    assert document |> LazyHTML.query("h1") |> LazyHTML.text() |> squish() == "Research w toku."
    assert document |> LazyHTML.query("h1 [data-part=underline]") |> LazyHTML.text() =~ "w toku."

    assert [@underline_path] =
             document |> LazyHTML.query("h1 [data-part=underline] svg[data-part=stroke] path") |> LazyHTML.attribute("d")

    assert has_class?(document, "h1 [data-part=underline] svg[data-part=stroke] path", "stroke-accent")

    assert ["7"] =
             document
             |> LazyHTML.query("h1 [data-part=underline] svg[data-part=stroke] path")
             |> LazyHTML.attribute("stroke-width")

    assert ["round"] =
             document
             |> LazyHTML.query("h1 [data-part=underline] svg[data-part=stroke] path")
             |> LazyHTML.attribute("stroke-linecap")

    assert has_class?(document, "h1 [data-part=underline] svg[data-part=stroke]", "-z-10")
  end

  test "the headline's underline ends with a rocket flying off it, hidden on phones" do
    assigns = %{}

    document = parse(~H|<UI.headline>
  Research
  <:underline>w toku.</:underline>
</UI.headline>|)

    rocket = "h1 [data-part=underline] svg[data-part=rocket][aria-hidden=true]"

    for class <- ~w(absolute left-full max-sm:hidden) do
      assert has_class?(document, rocket, class)
    end

    assert document |> LazyHTML.query(rocket <> " path.stroke-accent[stroke-dasharray]") |> Enum.count() == 1
    assert document |> LazyHTML.query(rocket <> " g[transform] path.fill-ink") |> Enum.count() == 1

    assert document |> LazyHTML.query(rocket <> " [data-moon-mark], " <> rocket <> " > path.fill-ink") |> Enum.count() ==
             0
  end

  test "the headline can render at a lower heading level" do
    assigns = %{}

    document = parse(~H|<UI.headline level="h2">
  Strony
  <:underline>i wyniki.</:underline>
</UI.headline>|)

    assert document |> LazyHTML.query("h1") |> Enum.count() == 0
    assert document |> LazyHTML.query("h2 [data-part=underline]") |> LazyHTML.text() =~ "i wyniki."
    assert has_class?(document, "h2", "leading-none")
  end

  test "the rocket is a decorative drawing with an ink body and a lime flame, sized by the caller" do
    assigns = %{}

    document = parse(~H|<UI.rocket class="size-10" />|)

    assert has_class?(document, "svg[data-rocket][aria-hidden=true]", "size-10")
    assert document |> LazyHTML.query("svg[data-rocket] path.fill-ink") |> Enum.count() == 1
    assert document |> LazyHTML.query("svg[data-rocket] path.fill-accent") |> Enum.count() == 1
  end

  test "the dark panel shows a mono top bar with context and note, then its content" do
    assigns = %{}

    document =
      parse(~H"""
      <UI.dark_panel id="panel" context="how it works" note="8 steps">
        <p id="panel-body">Content</p>
      </UI.dark_panel>
      """)

    for class <- ~w(bg-slate text-on-slate rounded-panel shadow-panel) do
      assert has_class?(document, "#panel", class)
    end

    assert has_class?(document, "#panel [data-part=top-bar]", "font-mono")
    assert document |> LazyHTML.query("#panel [data-part=top-bar] svg[data-moon-mark]") |> Enum.count() == 1
    assert document |> LazyHTML.query("#panel [data-part=context]") |> LazyHTML.text() == "dirmoon / how it works"
    assert document |> LazyHTML.query("#panel [data-part=note]") |> LazyHTML.text() == "8 steps"
    assert document |> LazyHTML.query("#panel #panel-body") |> Enum.count() == 1
  end

  test "a button without a destination is a real button at least 44px tall" do
    assigns = %{}

    document = parse(~H|<UI.button id="stop" variant="outline">Zatrzymaj</UI.button>|)

    assert ["button"] = document |> LazyHTML.query("button#stop") |> LazyHTML.attribute("type")
    assert ["outline"] = document |> LazyHTML.query("#stop") |> LazyHTML.attribute("data-variant")
    assert has_class?(document, "#stop", "min-h-target-min")
    assert has_class?(document, "#stop", "border-app-line-strong")
    assert has_class?(document, "#stop", "text-on-app")
  end

  test "a button with a destination renders as a link" do
    assigns = %{}

    document =
      parse(~H"""
      <UI.button id="go" variant="lime" navigate="/app/runs">Show</UI.button>
      <UI.button id="out" variant="ghost" href="/elsewhere">Reject</UI.button>
      """)

    assert ["/app/runs"] = document |> LazyHTML.query("a#go") |> LazyHTML.attribute("href")
    assert has_class?(document, "#go", "bg-accent")
    assert has_class?(document, "#go", "text-ink")
    assert ["/elsewhere"] = document |> LazyHTML.query("a#out") |> LazyHTML.attribute("href")
    assert has_class?(document, "#out", "text-on-app-muted")
  end

  test "the dark button is an ink fill for the light pages" do
    assigns = %{}

    document = parse(~H|<UI.button id="sign-in" variant="dark" type="submit">Zaloguj</UI.button>|)

    assert ["submit"] = document |> LazyHTML.query("button#sign-in") |> LazyHTML.attribute("type")
    assert has_class?(document, "#sign-in", "bg-ink")
    assert has_class?(document, "#sign-in", "text-white")
  end

  test "chips are 36px pill buttons and the dashed variant has a dashed outline" do
    assigns = %{}

    document = parse(~H|<UI.chip id="domain" variant="dashed">+ Domena</UI.chip>|)

    assert ["button"] = document |> LazyHTML.query("button#domain") |> LazyHTML.attribute("type")
    assert has_class?(document, "#domain", "min-h-9")
    assert has_class?(document, "#domain", "rounded-pill")
    assert has_class?(document, "#domain", "border-dashed")
    assert has_class?(document, "#domain", "border-app-line-strong")
    assert has_class?(document, "#domain", "text-on-app-2")
  end

  test "the outline chip is outlined on the app's grays" do
    assigns = %{}

    document = parse(~H|<UI.chip id="example" variant="outline">Example</UI.chip>|)

    assert has_class?(document, "#example", "min-h-9")
    assert has_class?(document, "#example", "border-app-line-strong")
    assert has_class?(document, "#example", "text-on-app-2")
    refute has_class?(document, "#example", "border-dashed")
  end

  test "an app sidebar link is 44px tall and the active one is filled and marked as the current page" do
    assigns = %{}

    document =
      parse(~H"""
      <UI.app_sidebar_link id="new" href="/app/research/new" variant="action" active>Nowy research</UI.app_sidebar_link>
      <UI.app_sidebar_link id="runs" href="/app/runs">Wyniki</UI.app_sidebar_link>
      """)

    for id <- ~w(#new #runs) do
      assert has_class?(document, id, "min-h-target-min")
    end

    assert ["page"] = document |> LazyHTML.query("a#new") |> LazyHTML.attribute("aria-current")
    assert has_class?(document, "#new", "bg-app-selected")
    assert has_class?(document, "#new", "border-app-line-strong")
    assert document |> LazyHTML.query("a#runs[aria-current]") |> Enum.count() == 0
    assert has_class?(document, "#runs", "border-transparent")
    assert has_class?(document, "#runs", "text-on-app-2")
  end

  test "a run status shows failed in amber, stopped muted and the rest as a pill" do
    assigns = %{}

    document =
      parse(~H"""
      <UI.run_status id="failed" status={:failed} label="Failed" />
      <UI.run_status id="stopped" status={:stopped} label="Stopped" />
      <UI.run_status id="running" status={:running} label="In progress" />
      """)

    assert has_class?(document, "#failed", "text-warn")
    assert document |> LazyHTML.query("#failed .hero-exclamation-triangle") |> Enum.count() == 1
    assert has_class?(document, "#stopped", "text-on-app-muted")
    assert has_class?(document, "#running", "rounded-pill")
    assert has_class?(document, "#running", "border-app-line-strong")
  end

  test "a stat tile shows its label above the value and can highlight the value" do
    assigns = %{}

    document = parse(~H|<UI.stat_tile id="tile" label="Average CPC" value="[CPC]" highlight />|)

    assert has_class?(document, "#tile", "bg-app-raised")
    assert document |> LazyHTML.query("#tile [data-part=label]") |> LazyHTML.text() == "Average CPC"
    assert document |> LazyHTML.query("#tile [data-part=value]") |> LazyHTML.text() == "[CPC]"
    assert has_class?(document, "#tile [data-part=value]", "text-accent")
  end

  test "a stat tile without highlight draws the value in the app's primary text" do
    assigns = %{}

    document = parse(~H|<UI.stat_tile id="tile" label="Average CPC" value="[CPC]" />|)

    assert has_class?(document, "#tile [data-part=value]", "text-on-app")
    refute has_class?(document, "#tile [data-part=value]", "text-accent")
  end

  test "the prompt box on the landing page is white with an ink border and the lime edge" do
    assigns = %{}

    document = parse(~H|<UI.prompt_box id="box">Content</UI.prompt_box>|)

    for class <- ~w(rounded-prompt bg-white border-ink shadow-prompt) do
      assert has_class?(document, "#box", class)
    end
  end

  test "the prompt box in the app is a raised gray card with no lime edge" do
    assigns = %{}

    document = parse(~H|<UI.prompt_box id="box" surface="app">Content</UI.prompt_box>|)

    for class <- ~w(rounded-prompt bg-app-raised border border-app-line-strong) do
      assert has_class?(document, "#box", class)
    end

    refute has_class?(document, "#box", "shadow-prompt")
    refute has_class?(document, "#box", "bg-white")
  end

  test "the run stopped note links to the run's screen in the accent on the app's grays" do
    run = insert(:run)
    assigns = %{run: run}

    document =
      parse(~H"""
      <UI.run_stopped_note id="note" link_id="resume" run={@run}>
        Research jest zatrzymany.
      </UI.run_stopped_note>
      """)

    assert has_class?(document, "#note", "text-on-app-2")
    assert ["/app/runs/#{run.id}"] == document |> LazyHTML.query("#resume") |> LazyHTML.attribute("href")
  end

  test "the stylesheet defines every design token with the value from the handover" do
    handover = "docs/design/tokens.css" |> File.read!() |> css_variables()
    stylesheet = "assets/css/tokens.css" |> File.read!() |> css_variables()

    assert map_size(handover) > 0

    for {name, value} <- handover do
      assert Map.get(stylesheet, name) == value, "#{name} should be #{value}"
    end
  end

  test "the app surface tokens are an explicit allowance with pinned values, and no other colour token exists" do
    handover = "docs/design/tokens.css" |> File.read!() |> css_variables()
    stylesheet = "assets/css/tokens.css" |> File.read!() |> css_variables()

    for {name, value} <- @app_surface_tokens do
      assert Map.get(stylesheet, name) == value, "#{name} should be #{value}"
      refute Map.has_key?(handover, name), "#{name} is a handover token, not an app allowance"
    end

    colour_tokens =
      stylesheet
      |> Enum.filter(fn {_name, value} -> value =~ ~r/^#[0-9a-fA-F]{3,8}$/ end)
      |> Map.new()

    handover_colour_tokens = Map.filter(handover, fn {_name, value} -> value =~ ~r/^#[0-9a-fA-F]{3,8}$/ end)

    assert colour_tokens == Map.merge(handover_colour_tokens, @app_surface_tokens)
  end

  test "every app surface token is mapped to a Tailwind colour utility" do
    stylesheet = File.read!("assets/css/app.css")

    for {name, utility} <- [
          {"--app-bg", "app"},
          {"--app-chrome", "app-chrome"},
          {"--app-raised", "app-raised"},
          {"--app-selected", "app-selected"},
          {"--app-field", "app-field"},
          {"--app-line", "app-line"},
          {"--app-line-strong", "app-line-strong"},
          {"--on-app", "on-app"},
          {"--on-app-2", "on-app-2"},
          {"--on-app-muted", "on-app-muted"}
        ] do
      assert stylesheet =~ "--color-#{utility}: var(#{name});", "#{name} is not mapped to #{utility}"
    end
  end

  test "no signed-in screen or the app shell uses a slate utility" do
    live_sources = Path.wildcard("lib/dirmoon_web/live/**/*.ex")
    sources = ["lib/dirmoon_web/components/layouts.ex" | live_sources]

    assert "lib/dirmoon_web/live/new_research_live.ex" in live_sources

    for path <- sources, source = File.read!(path) do
      refute source =~ @slate_utility, "#{path} uses a slate utility"
      refute source =~ ~r/"slate"/, "#{path} names the slate surface"
    end
  end

  test "the landing page keeps the slate dark panel", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert has_class?(document, "#journey-steps-report-panel[data-surface=dark]", "bg-slate")
    assert has_class?(document, "#journey-steps-report-panel [data-part=top-bar]", "border-slate-line")
    assert "lib/dirmoon_web/components/ui.ex" |> File.read!() |> String.match?(@slate_utility)
  end

  test "outside tokens.css no stylesheet or component holds a literal colour" do
    sources =
      ~w(
        assets/css/app.css
        assets/css/fonts.css
        lib/dirmoon_web/components/ui.ex
        lib/dirmoon_web/components/layouts.ex
        lib/dirmoon_web/components/layouts/root.html.heex
        lib/dirmoon_web/components/core_components.ex
        lib/dirmoon_web/run_display.ex
      ) ++ Path.wildcard("lib/dirmoon_web/live/**/*.ex")

    for path <- sources, source = File.read!(path) do
      refute source =~ ~r/#[0-9a-fA-F]{3}(?:[0-9a-fA-F]{3})?(?:[0-9a-fA-F]{2})?\b(?![-\w])/,
             "#{path} has a hex colour"

      refute source =~ ~r/\b(?:rgba?|hsla?|oklch|oklab|lab|lch|hwb)\(/, "#{path} has a colour function"
    end
  end

  test "the components use no Tailwind palette colours and no daisyUI classes" do
    palette =
      ~w(slate gray zinc neutral stone red orange amber yellow lime green emerald teal cyan sky blue indigo violet purple fuchsia pink rose)

    palette_class = ~r/\b[a-z-]+-(?:#{Enum.join(palette, "|")})-\d{2,3}\b/

    daisy_classes =
      ~w(btn navbar badge card-body alert toast fieldset label input select textarea checkbox table table-zebra list list-row list-col-grow theme_toggle)

    daisy_colour_class =
      ~r/^(?:[a-z]+-)?(?:base-\d{3}|base-content|primary|secondary|neutral|info|success|warning|error)(?:-content)?(?:\/\d+)?$/

    for path <- ~w(
          lib/dirmoon_web/components/ui.ex
          lib/dirmoon_web/components/layouts.ex
          lib/dirmoon_web/components/core_components.ex
        ),
        source = File.read!(path) do
      refute source =~ palette_class, "#{path} uses a Tailwind palette colour"

      for class <- class_names(source) do
        refute class in daisy_classes, "#{path} uses the daisyUI class #{class}"
        refute class =~ daisy_colour_class, "#{path} uses the daisyUI colour class #{class}"
      end
    end
  end

  test "the stylesheet loads no daisyUI plugin" do
    stylesheet = File.read!("assets/css/app.css")

    refute stylesheet =~ ~r/daisyui/i
  end

  test "the wordmark links the moon mark and the dirmoon name to the given page" do
    assigns = %{}

    document = parse(~H|<UI.wordmark href="/start" />|)

    assert ["/start"] = document |> LazyHTML.query("a[data-part=brand]") |> LazyHTML.attribute("href")
    assert document |> LazyHTML.query("a[data-part=brand] svg[data-moon-mark]") |> Enum.count() == 1
    assert document |> LazyHTML.query("a[data-part=brand]") |> LazyHTML.text() |> squish() == "dirmoon"

    for class <- ~w(font-extrabold text-[21px] text-ink min-h-target-min) do
      assert has_class?(document, "a[data-part=brand]", class)
    end
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

  defp squish(text), do: text |> String.split() |> Enum.join(" ")

  defp class_names(source) do
    ~r/class=(\{.*?\}|"[^"]*")/s
    |> Regex.scan(source, capture: :all_but_first)
    |> Enum.flat_map(fn [attribute] -> Regex.scan(~r/"([^"]*)"/, attribute, capture: :all_but_first) end)
    |> Enum.flat_map(fn [classes] -> String.split(classes) end)
    |> Enum.map(fn class -> class |> String.split(":") |> List.last() end)
  end

  defp css_variables(css) do
    ~r/(--[\w-]+)\s*:\s*([^;]+);/
    |> Regex.scan(css, capture: :all_but_first)
    |> Map.new(fn [name, value] -> {name, String.trim(value)} end)
  end
end
