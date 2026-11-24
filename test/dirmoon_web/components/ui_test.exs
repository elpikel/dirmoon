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

  test "the moon mark is decorative unless it is given a label" do
    assigns = %{}

    decorative = parse(~H"<UI.moon_mark />")
    labelled = parse(~H|<UI.moon_mark label="dirmoon" />|)

    assert ["true"] = decorative |> LazyHTML.query("svg") |> LazyHTML.attribute("aria-hidden")
    assert ["dirmoon"] = labelled |> LazyHTML.query("svg") |> LazyHTML.attribute("aria-label")
  end

  test "the nav card floats with the mark and wordmark on the left and its links on the right" do
    assigns = %{}

    document =
      parse(~H"""
      <UI.nav_card id="nav">
        <UI.nav_link href="/somewhere" active>Wyniki</UI.nav_link>
        <UI.button variant="dark" href="/new">Nowy research</UI.button>
      </UI.nav_card>
      """)

    for class <- ~w(bg-page border-line rounded-nav shadow-nav) do
      assert has_class?(document, "#nav", class)
    end

    assert document |> LazyHTML.query("#nav [data-part=brand] svg[data-moon-mark]") |> Enum.count() == 1
    assert document |> LazyHTML.query("#nav [data-part=brand]") |> LazyHTML.text() =~ "dirmoon"
    assert has_class?(document, "#nav [data-part=brand]", "font-extrabold")
    assert has_class?(document, "#nav [data-part=brand]", "text-[21px]")
    assert ["page"] = document |> LazyHTML.query("#nav nav a[href='/somewhere']") |> LazyHTML.attribute("aria-current")
    assert document |> LazyHTML.query("#nav nav a[href='/new'][data-variant=dark]") |> Enum.count() == 1
  end

  test "an inactive nav link is muted and not marked as the current page" do
    assigns = %{}

    document = parse(~H|<UI.nav_link href="/elsewhere">Strony</UI.nav_link>|)

    assert document |> LazyHTML.query("a[aria-current]") |> Enum.count() == 0
    assert has_class?(document, "a", "text-body-muted")
    assert has_class?(document, "a", "min-h-target-min")
  end

  test "the eyebrow tag is a small mono uppercase label on the chip fill" do
    assigns = %{}

    document = parse(~H|<UI.eyebrow id="tag">Popyt z Google</UI.eyebrow>|)

    for class <- ~w(font-mono text-xs uppercase tracking-[0.1em] bg-chip rounded-chip) do
      assert has_class?(document, "#tag", class)
    end

    assert document |> LazyHTML.query("#tag") |> LazyHTML.text() == "Popyt z Google"
  end

  test "the headline wraps its underline phrase in the lime stroke placed behind the text" do
    assigns = %{}

    document =
      parse(~H"""
      <UI.headline id="hero">
        Research
        <:underline>w toku.</:underline>
      </UI.headline>
      """)

    assert has_class?(document, "h1#hero", "font-extrabold")
    assert has_class?(document, "h1#hero", "isolate")
    assert document |> LazyHTML.query("h1#hero") |> LazyHTML.text() |> squish() == "Research w toku."
    assert document |> LazyHTML.query("#hero [data-part=underline]") |> LazyHTML.text() =~ "w toku."

    assert [@underline_path] =
             document |> LazyHTML.query("#hero [data-part=underline] svg path") |> LazyHTML.attribute("d")

    assert has_class?(document, "#hero [data-part=underline] svg path", "stroke-accent")

    assert ["7"] =
             document |> LazyHTML.query("#hero [data-part=underline] svg path") |> LazyHTML.attribute("stroke-width")

    assert ["round"] =
             document |> LazyHTML.query("#hero [data-part=underline] svg path") |> LazyHTML.attribute("stroke-linecap")

    assert has_class?(document, "#hero [data-part=underline] svg", "-z-10")
  end

  test "the headline can render at a lower heading level" do
    assigns = %{}

    document = parse(~H|<UI.headline id="sub" level="h2">Strony</UI.headline>|)

    assert document |> LazyHTML.query("h2#sub") |> Enum.count() == 1
    assert document |> LazyHTML.query("#sub [data-part=underline]") |> Enum.count() == 0
  end

  test "the dark panel shows a mono top bar with context and note, then the status row with the mark" do
    assigns = %{}

    document =
      parse(~H"""
      <UI.dark_panel id="panel" context="wynajem kamperów" note="Dane przykładowe">
        <:status>Sprawdzam, kto odpowiada na najlepsze frazy.</:status>
        <p id="panel-body">Treść</p>
      </UI.dark_panel>
      """)

    for class <- ~w(bg-slate text-on-slate rounded-panel shadow-panel) do
      assert has_class?(document, "#panel", class)
    end

    assert has_class?(document, "#panel [data-part=top-bar]", "font-mono")
    assert document |> LazyHTML.query("#panel [data-part=context]") |> LazyHTML.text() == "dirmoon / wynajem kamperów"
    assert document |> LazyHTML.query("#panel [data-part=note]") |> LazyHTML.text() == "Dane przykładowe"
    assert has_class?(document, "#panel [data-part=status]", "bg-slate-raised")
    assert document |> LazyHTML.query("#panel [data-part=status] svg[data-moon-mark]") |> Enum.count() == 1

    assert document |> LazyHTML.query("#panel [data-part=status]") |> LazyHTML.text() |> squish() ==
             "Sprawdzam, kto odpowiada na najlepsze frazy."

    assert document |> LazyHTML.query("#panel #panel-body") |> Enum.count() == 1
  end

  test "the dark panel leaves out the status row and the note when none is given" do
    assigns = %{}

    document = parse(~H|<UI.dark_panel id="plain" context="jak to działa">Treść</UI.dark_panel>|)

    assert document |> LazyHTML.query("#plain [data-part=status]") |> Enum.count() == 0
    assert document |> LazyHTML.query("#plain [data-part=note]") |> Enum.count() == 0
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

  test "chips are 36px pills and the dashed variant has a dashed outline" do
    assigns = %{}

    document =
      parse(~H"""
      <UI.chip id="mode" variant="dark">Nowy pomysł</UI.chip>
      <UI.chip id="domain" variant="dashed">+ Domena</UI.chip>
      """)

    for id <- ~w(#mode #domain) do
      assert has_class?(document, id, "min-h-9")
      assert has_class?(document, id, "rounded-pill")
    end

    assert has_class?(document, "#mode", "bg-ink")
    assert has_class?(document, "#domain", "border-dashed")
    assert has_class?(document, "#domain", "border-line-dashed")
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
