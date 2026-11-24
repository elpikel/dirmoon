defmodule DirmoonWeb.UITest do
  use DirmoonWeb.ConnCase, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias DirmoonWeb.UI

  @crescent_path "M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"
  @underline_path "M4 14 C 120 4, 240 22, 360 12 S 540 6, 596 12"

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
        <UI.nav_link href="/somewhere">Zaloguj się</UI.nav_link>
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
    assert ["Główna"] = document |> LazyHTML.query("#nav nav") |> LazyHTML.attribute("aria-label")
    assert document |> LazyHTML.query("#nav nav a[href='/somewhere']") |> Enum.count() == 1
  end

  test "a nav link is muted and not marked as the current page" do
    assigns = %{}

    document = parse(~H|<UI.nav_link href="/elsewhere">Strony</UI.nav_link>|)

    assert document |> LazyHTML.query("a[aria-current]") |> Enum.count() == 0
    assert has_class?(document, "a", "text-body-muted")
    assert has_class?(document, "a", "min-h-target-min")
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
             document |> LazyHTML.query("h1 [data-part=underline] svg path") |> LazyHTML.attribute("d")

    assert has_class?(document, "h1 [data-part=underline] svg path", "stroke-accent")

    assert ["7"] =
             document |> LazyHTML.query("h1 [data-part=underline] svg path") |> LazyHTML.attribute("stroke-width")

    assert ["round"] =
             document |> LazyHTML.query("h1 [data-part=underline] svg path") |> LazyHTML.attribute("stroke-linecap")

    assert has_class?(document, "h1 [data-part=underline] svg", "-z-10")
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

  test "the dark panel shows a mono top bar with context and note, then its content" do
    assigns = %{}

    document =
      parse(~H"""
      <UI.dark_panel id="panel" context="jak to działa" note="9 kroków">
        <p id="panel-body">Treść</p>
      </UI.dark_panel>
      """)

    for class <- ~w(bg-slate text-on-slate rounded-panel shadow-panel) do
      assert has_class?(document, "#panel", class)
    end

    assert has_class?(document, "#panel [data-part=top-bar]", "font-mono")
    assert document |> LazyHTML.query("#panel [data-part=top-bar] svg[data-moon-mark]") |> Enum.count() == 1
    assert document |> LazyHTML.query("#panel [data-part=context]") |> LazyHTML.text() == "dirmoon / jak to działa"
    assert document |> LazyHTML.query("#panel [data-part=note]") |> LazyHTML.text() == "9 kroków"
    assert document |> LazyHTML.query("#panel #panel-body") |> Enum.count() == 1
  end

  test "a button without a destination is a real button at least 44px tall" do
    assigns = %{}

    document = parse(~H|<UI.button id="stop" variant="outline">Zatrzymaj</UI.button>|)

    assert ["button"] = document |> LazyHTML.query("button#stop") |> LazyHTML.attribute("type")
    assert ["outline"] = document |> LazyHTML.query("#stop") |> LazyHTML.attribute("data-variant")
    assert has_class?(document, "#stop", "min-h-target-min")
    assert has_class?(document, "#stop", "border-slate-line-strong")
  end

  test "a button with a destination renders as a link" do
    assigns = %{}

    document =
      parse(~H"""
      <UI.button id="go" variant="lime" navigate="/app/runs">Pokaż</UI.button>
      <UI.button id="out" variant="ghost" href="/elsewhere">Odrzuć</UI.button>
      """)

    assert ["/app/runs"] = document |> LazyHTML.query("a#go") |> LazyHTML.attribute("href")
    assert has_class?(document, "#go", "bg-accent")
    assert has_class?(document, "#go", "text-ink")
    assert ["/elsewhere"] = document |> LazyHTML.query("a#out") |> LazyHTML.attribute("href")
  end

  test "chips are 36px pill buttons and the dashed variant has a dashed outline" do
    assigns = %{}

    document = parse(~H|<UI.chip id="domain" variant="dashed">+ Domena</UI.chip>|)

    assert ["button"] = document |> LazyHTML.query("button#domain") |> LazyHTML.attribute("type")
    assert has_class?(document, "#domain", "min-h-9")
    assert has_class?(document, "#domain", "rounded-pill")
    assert has_class?(document, "#domain", "border-dashed")
    assert has_class?(document, "#domain", "border-line-dashed")
  end

  test "the slate chip is outlined on the dark surface" do
    assigns = %{}

    document = parse(~H|<UI.chip id="example" variant="slate">Przykład</UI.chip>|)

    assert has_class?(document, "#example", "min-h-9")
    assert has_class?(document, "#example", "border-slate-line-strong")
    assert has_class?(document, "#example", "text-on-slate-2")
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
    assert has_class?(document, "#new", "bg-slate-selected")
    assert has_class?(document, "#new", "border-slate-line-strong")
    assert document |> LazyHTML.query("a#runs[aria-current]") |> Enum.count() == 0
    assert has_class?(document, "#runs", "border-transparent")
    assert has_class?(document, "#runs", "text-on-slate-2")
  end

  test "a run status shows done in lime, failed in amber, stopped muted and the rest as a pill" do
    assigns = %{}

    document =
      parse(~H"""
      <UI.run_status id="done" status={:done} label="Gotowy" />
      <UI.run_status id="failed" status={:failed} label="Błąd" />
      <UI.run_status id="stopped" status={:stopped} label="Zatrzymany" />
      <UI.run_status id="running" status={:running} label="W toku" />
      """)

    assert has_class?(document, "#done", "text-accent")
    assert document |> LazyHTML.query("#done .hero-check-mini") |> Enum.count() == 1
    assert has_class?(document, "#failed", "text-warn")
    assert document |> LazyHTML.query("#failed .hero-exclamation-triangle") |> Enum.count() == 1
    assert has_class?(document, "#stopped", "text-on-slate-muted")
    assert has_class?(document, "#running", "rounded-pill")
  end

  test "a stat tile shows its label above the value and can highlight the value" do
    assigns = %{}

    document = parse(~H|<UI.stat_tile id="tile" label="Średni CPC" value="[CPC]" highlight />|)

    assert has_class?(document, "#tile", "bg-slate-raised")
    assert document |> LazyHTML.query("#tile [data-part=label]") |> LazyHTML.text() == "Średni CPC"
    assert document |> LazyHTML.query("#tile [data-part=value]") |> LazyHTML.text() == "[CPC]"
    assert has_class?(document, "#tile [data-part=value]", "text-accent")
  end

  test "the stylesheet defines every design token with the value from the handover" do
    handover = "docs/design/tokens.css" |> File.read!() |> css_variables()
    stylesheet = "assets/css/tokens.css" |> File.read!() |> css_variables()

    assert map_size(handover) > 0

    for {name, value} <- handover do
      assert Map.get(stylesheet, name) == value, "#{name} should be #{value}"
    end
  end

  test "outside tokens.css no stylesheet or component holds a literal colour" do
    sources = ~w(
      assets/css/app.css
      assets/css/fonts.css
      lib/dirmoon_web/components/ui.ex
      lib/dirmoon_web/components/layouts.ex
      lib/dirmoon_web/components/layouts/root.html.heex
      lib/dirmoon_web/components/core_components.ex
    )

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
