defmodule DirmoonWeb.UI do
  @moduledoc """
  dirmoon's design-system function components, from `docs/design/README.md`
  section 8.2.

  Every colour, font, radius and the shadows come from the token utilities mapped
  in `assets/css/app.css` (values in `assets/css/tokens.css`). Components are
  presentational: callers pass data and event attributes in.

  Stable hooks for tests: each component's root carries an `id` when given,
  and its inner parts carry `data-part` attributes.
  """
  use Phoenix.Component
  use DirmoonWeb, :verified_routes

  import DirmoonWeb.CoreComponents, only: [icon: 1]

  @crescent_path "M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"
  @underline_path "M4 14 C 120 4, 240 22, 360 12 S 540 6, 596 12"

  @doc """
  Renders the crescent moon mark, inline as SVG and decorative: the text next
  to it names the brand. Placeholder quality: the owner has not approved a logo.

      <.moon_mark />
      <.moon_mark tone="accent" size={14} />
  """
  attr :tone, :string, default: "ink", values: ~w(ink accent), doc: "ink on light, accent on dark"
  attr :size, :integer, default: 24, doc: "width and height in pixels"

  def moon_mark(assigns) do
    assigns = assign(assigns, :path, @crescent_path)

    ~H"""
    <svg
      data-moon-mark
      viewBox="0 0 24 24"
      width={@size}
      height={@size}
      aria-hidden="true"
      class="flex-none"
    >
      <path d={@path} class={moon_fill(@tone)} />
    </svg>
    """
  end

  @doc """
  Renders the brand: the moon mark and "dirmoon" (800 weight, 21px) as one
  link, as in the nav card and above the sign-in card.

      <.wordmark href="/" />
  """
  attr :href, :string, required: true, doc: "where the brand links to"

  def wordmark(assigns) do
    ~H"""
    <.link
      href={@href}
      data-part="brand"
      class="flex min-h-target-min items-center gap-[9px] text-[21px] font-extrabold tracking-[-0.03em] text-ink no-underline"
    >
      <.moon_mark />
      <span>dirmoon</span>
    </.link>
    """
  end

  @doc """
  Renders the landing page's floating nav card: the moon mark and "dirmoon"
  linking to the landing page on the left, the inner block (nav links) on the
  right. It wraps onto two rows on narrow screens.

      <.nav_card id="landing-nav">
        <.nav_link href={~p"/users/log-in"}>Zaloguj się</.nav_link>
      </.nav_card>
  """
  attr :id, :string, required: true
  slot :inner_block, required: true

  def nav_card(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "mx-auto flex w-full max-w-content flex-wrap items-center justify-between gap-x-6 gap-y-2",
        "rounded-nav border border-line bg-page py-2.5 pr-3 pl-[22px] shadow-nav max-sm:pl-4"
      ]}
    >
      <.wordmark href={~p"/"} />
      <nav
        aria-label="Główna"
        class="flex flex-wrap items-center gap-x-7 gap-y-2 text-sm font-medium max-sm:gap-x-5"
      >
        {render_slot(@inner_block)}
      </nav>
    </div>
    """
  end

  @doc """
  Renders a muted text link for the nav card.

      <.nav_link href={~p"/users/log-in"}>Zaloguj się</.nav_link>
  """
  attr :rest, :global, include: ~w(href)
  slot :inner_block, required: true

  def nav_link(assigns) do
    ~H"""
    <.link
      class="inline-flex min-h-target-min items-center text-body-muted no-underline transition-colors duration-150 hover:text-ink"
      {@rest}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc """
  Renders a link in the app shell's sidebar, on the app chrome. The `action` variant
  is outlined (the "Nowy research" entry), the `link` variant is plain text.
  The active one is the current page: filled and marked `aria-current`.

      <.app_sidebar_link href="/app/research/new" variant="action">Nowy research</.app_sidebar_link>
      <.app_sidebar_link href="/app/runs" active>Wyniki</.app_sidebar_link>
  """
  attr :variant, :string, default: "link", values: ~w(action link)
  attr :active, :boolean, default: false, doc: "marks the current page"
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(href)
  slot :inner_block, required: true

  def app_sidebar_link(assigns) do
    ~H"""
    <.link
      aria-current={@active && "page"}
      data-variant={@variant}
      class={[
        "inline-flex min-h-target-min items-center gap-2.5 rounded-control px-3 text-sm no-underline",
        "transition-colors duration-150",
        sidebar_variant_class(@variant),
        if(@active,
          do: "bg-app-selected font-semibold text-on-app",
          else: "text-on-app-2 hover:bg-app-raised hover:text-on-app"
        ),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc """
  Renders the eyebrow tag above a headline: mono, uppercase, on the chip fill.

      <.eyebrow>Popyt z Google, zanim napiszesz linijkę kodu</.eyebrow>
  """
  slot :inner_block, required: true

  def eyebrow(assigns) do
    ~H"""
    <span class="rounded-chip bg-chip px-3 py-[7px] font-mono text-xs uppercase tracking-[0.1em] text-ink">{render_slot(
      @inner_block
    )}</span>
    """
  end

  @doc """
  Renders a landing page headline: Inter 800, tight tracking, line height
  about 1. The `underline` slot holds the one phrase that carries the lime
  hand-drawn underline; it is rendered after the inner block.

      <.headline size="hero">
        Zanim zbudujesz, sprawdź,
        <:underline>czy ktoś tego szuka.</:underline>
      </.headline>

      <.headline level="h2">Masz pomysł? <:underline>Sprawdź go najpierw.</:underline></.headline>
  """
  attr :level, :string, default: "h1", values: ~w(h1 h2), doc: "the heading element"

  attr :size, :string,
    default: "page",
    values: ~w(hero page),
    doc: "hero is the landing hero (up to 84px), page is the other headlines (up to 64px)"

  slot :inner_block
  slot :underline, required: true, doc: "the phrase drawn over the lime underline"

  def headline(assigns) do
    assigns = assign(assigns, :underline_path, @underline_path)

    ~H"""
    <.dynamic_tag
      tag_name={@level}
      class={["relative isolate m-0 font-extrabold text-balance", headline_size_class(@size)]}
    >
      {render_slot(@inner_block)}
      <span data-part="underline" class="relative inline-block">
        {render_slot(@underline)}<svg
          aria-hidden="true"
          viewBox="0 0 600 24"
          preserveAspectRatio="none"
          class="absolute bottom-[-0.14em] left-0 -z-10 h-[0.24em] w-full"
        ><path
          d={@underline_path}
          fill="none"
          stroke-width="7"
          stroke-linecap="round"
          vector-effect="non-scaling-stroke"
          class="stroke-accent"
        /></svg>
      </span>
    </.dynamic_tag>
    """
  end

  @doc """
  Renders the landing page's dark slate panel (the signed-in app uses the
  gray app tokens instead): a mono top bar with
  `dirmoon / <context>` on the left and a note on the right, then the inner
  block.

      <.dark_panel id="how-it-works" context="jak to działa" note="9 kroków">
        ...
      </.dark_panel>
  """
  attr :id, :string, required: true
  attr :context, :string, required: true, doc: "shown as `dirmoon / <context>` in the top bar"
  attr :note, :string, required: true, doc: "short mono note at the right of the top bar"
  slot :inner_block, required: true

  def dark_panel(assigns) do
    ~H"""
    <section
      id={@id}
      data-surface="dark"
      class="w-full overflow-hidden rounded-panel bg-slate text-left text-on-slate shadow-panel"
    >
      <div
        data-part="top-bar"
        class="flex flex-wrap items-center justify-between gap-3 border-b border-slate-line px-5 py-3.5 font-mono"
      >
        <div class="flex items-center gap-2.5 text-xs text-on-slate-muted">
          <.moon_mark tone="accent" size={14} />
          <span data-part="context">dirmoon / {@context}</span>
        </div>
        <span data-part="note" class="text-[11px] text-on-slate-muted">{@note}</span>
      </div>
      {render_slot(@inner_block)}
    </section>
    """
  end

  @doc """
  Renders a button, or a link styled as a button when given `href` or
  `navigate`. Always at least 44px tall.

  Variants: `dark` (ink fill, on light), `lime` (the one primary action in
  the app), `outline` (on the app's grays) and `ghost` (text only, on the
  app's grays).

      <.button variant="dark" href="/app/research/new">Nowy research</.button>
      <.button variant="lime" size="large" phx-click="choose">Wybierz niszę</.button>
      <.button variant="outline">Zatrzymaj</.button>
  """
  attr :variant, :string, required: true, values: ~w(dark lime outline ghost)

  attr :size, :string,
    default: "default",
    values: ~w(default large),
    doc: "default is 44px at 14px text (nav), large is 48px at 15px text (panel actions)"

  attr :type, :string, default: "button", doc: "the button type; ignored for links"
  attr :class, :any, default: nil

  attr :rest, :global, include: ~w(href navigate name disabled form target rel)

  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    assigns =
      assign(assigns, :classes, [
        "inline-flex cursor-pointer items-center justify-center gap-2 rounded-control font-sans no-underline",
        "transition-[background-color,color,filter] duration-150 active:translate-y-px",
        "disabled:cursor-not-allowed disabled:opacity-60 phx-submit-loading:opacity-75",
        button_size_class(assigns.size),
        button_variant_class(assigns.variant),
        assigns.class
      ])

    if rest[:href] || rest[:navigate] do
      ~H"""
      <.link data-variant={@variant} class={@classes} {@rest}>{render_slot(@inner_block)}</.link>
      """
    else
      ~H"""
      <button type={@type} data-variant={@variant} class={@classes} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders a 36px pill chip as a button, on the signed-in app's grays.

  Variants: `dashed` (optional fields in the prompt box footer, "+ Domena")
  and `outline` (the example prompts).

      <.chip variant="dashed" phx-click="show_domain">+ Domena</.chip>
      <.chip variant="outline" phx-click="use_example" phx-value-number="1">Przykład</.chip>
  """
  attr :variant, :string, required: true, values: ~w(dashed outline)
  attr :rest, :global
  slot :inner_block, required: true

  def chip(assigns) do
    ~H"""
    <button
      type="button"
      data-variant={@variant}
      class={[
        "inline-flex min-h-9 cursor-pointer items-center gap-1.5 rounded-pill font-sans text-[13px]",
        "transition-colors duration-150",
        chip_variant_class(@variant)
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Renders the prompt box, radius 22. On the light landing page it is white
  with a 1.5px ink border and the lime edge under it; in the signed-in app
  (`surface="app"`) it is a raised gray card with a 1px strong hairline and no
  edge, so the lime submit button stays the one accent. The inner block lays
  out its content.

      <.prompt_box class="flex flex-col">...</.prompt_box>
      <.prompt_box surface="app" class="flex flex-col">...</.prompt_box>
  """
  attr :surface, :string, default: "light", values: ~w(light app), doc: "the landing page or the signed-in app"
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def prompt_box(assigns) do
    ~H"""
    <div
      class={["rounded-prompt text-left", prompt_box_surface_class(@surface), @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders the dark "jak to działa" panel: the nine Steps summed up in four
  Step Groups (01–02 Frazy, 03–04 Popyt, 05–07 Konkurencja, 08–09 Strona), with
  its caption below. Landing page only: the signed-in app has no pitch.

      <.how_it_works id="how-it-works" class="mt-20" />
  """
  attr :id, :string, default: "how-it-works"
  attr :class, :any, default: nil

  def how_it_works(assigns) do
    assigns = assign(assigns, :step_groups, how_it_works_step_groups())

    ~H"""
    <figure class={["m-0 flex w-full flex-col items-center gap-4", @class]}>
      <.dark_panel
        id={@id}
        context="jak to działa"
        note="9 kroków, jedna decyzja po Twojej stronie"
      >
        <ol class="m-0 grid list-none grid-cols-[repeat(auto-fit,minmax(min(240px,100%),1fr))] p-0">
          <li
            :for={step_group <- @step_groups}
            class="flex flex-col gap-2.5 border-r border-b border-slate-line px-6 pt-6 pb-7 last:border-r-0"
          >
            <span data-part="step-group-steps" class="font-mono text-xs text-accent">{step_group.steps}</span>
            <span data-part="step-group-name" class="text-xl font-bold tracking-[-0.01em]">
              {step_group.name}
            </span>
            <p class="m-0 text-[15px] leading-[1.55] text-on-slate-2">{step_group.summary}</p>
          </li>
        </ol>
      </.dark_panel>
      <figcaption class="font-mono text-xs text-body-muted">
        Ryc. 1 · Cztery etapy jednego researchu.
      </figcaption>
    </figure>
    """
  end

  @doc """
  Renders a Research Run's status label in the app, as in the runs list:
  done with a lime check, failed with a warning icon, stopped muted, and
  running or awaiting a choice as an outlined pill. The caller passes the
  Polish label.

      <.run_status id="run-1-status" status={:done} label="Gotowy" />
  """
  attr :id, :string, required: true
  attr :status, :atom, required: true
  attr :label, :string, required: true

  def run_status(%{status: :done} = assigns) do
    ~H"""
    <span id={@id} class="flex items-center gap-1.5 text-accent">
      <.icon name="hero-check-mini" class="size-[13px]" />{@label}
    </span>
    """
  end

  def run_status(%{status: :failed} = assigns) do
    ~H"""
    <span id={@id} class="flex items-center gap-1.5 text-warn">
      <.icon name="hero-exclamation-triangle" class="size-[13px]" />{@label}
    </span>
    """
  end

  def run_status(%{status: :stopped} = assigns) do
    ~H"""
    <span id={@id} class="text-on-app-muted">{@label}</span>
    """
  end

  def run_status(assigns) do
    ~H"""
    <span
      id={@id}
      class="rounded-pill border border-app-line-strong px-[9px] py-[3px] text-on-app"
    >
      {@label}
    </span>
    """
  end

  @doc """
  Renders a stat tile in the app: a small label above a large value.
  `highlight` draws the value in the accent.

      <.stat_tile label="Wyszukiwania / mies." value={@volume} />
      <.stat_tile label="Wypożyczalnie w top 10" value="0" highlight />
  """
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :highlight, :boolean, default: false
  attr :rest, :global

  def stat_tile(assigns) do
    ~H"""
    <div
      class="flex flex-col gap-1.5 rounded-tile border border-app-line-strong bg-app-raised px-4 py-3.5"
      {@rest}
    >
      <span data-part="label" class="text-xs text-on-app-2">{@label}</span>
      <span
        data-part="value"
        class={[
          "text-[26px] font-extrabold tracking-[-0.03em]",
          if(@highlight, do: "text-accent", else: "text-on-app")
        ]}
      >{@value}</span>
    </div>
    """
  end

  @doc """
  Renders the note in the app that the research is stopped and must be resumed
  before the screen can go on, with a link to the run's screen, where the User
  resumes it. The inner block says what waits for the resume.

      <.run_stopped_note id="results-run-stopped" link_id="results-resume-link" run={@run}>
        Research jest zatrzymany. Wznów go, żeby wybrać niszę.
      </.run_stopped_note>
  """
  attr :id, :string, required: true
  attr :link_id, :string, required: true, doc: "id of the link to the run's screen"
  attr :run, :any, required: true, doc: "the stopped run, linked to by id"
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def run_stopped_note(assigns) do
    ~H"""
    <p id={@id} class={["m-0 text-[15px] leading-normal text-on-app-2", @class]}>
      {render_slot(@inner_block)}
      <.link
        id={@link_id}
        navigate={~p"/app/runs/#{@run}"}
        class="inline-flex min-h-target-min items-center font-medium text-accent underline underline-offset-4"
      >
        Przejdź do researchu
      </.link>
    </p>
    """
  end

  defp how_it_works_step_groups do
    [
      %{
        steps: "01–02",
        name: "Frazy",
        summary: "Z opisu powstają frazy startowe, a API rozwija je w realnie wpisywane zapytania."
      },
      %{
        steps: "03–04",
        name: "Popyt",
        summary: "Wyszukiwania miesięcznie w kraju i w mieście, CPC i trend z 12 miesięcy. Frazy łączę w nisze."
      },
      %{
        steps: "05–07",
        name: "Konkurencja",
        summary: "Kto dziś odpowiada na najlepsze frazy i jak słaba jest pierwsza strona wyników."
      },
      %{
        steps: "08–09",
        name: "Strona",
        summary: "Wybierasz niszę. Dostajesz brief i treść gotową do publikacji."
      }
    ]
  end

  defp moon_fill("ink"), do: "fill-ink"
  defp moon_fill("accent"), do: "fill-accent"

  defp headline_size_class("hero"), do: "max-w-[1000px] text-[clamp(40px,5.8vw,84px)] leading-[0.98] tracking-[-0.045em]"

  defp headline_size_class("page"), do: "max-w-[900px] text-[clamp(36px,4.6vw,64px)] leading-none tracking-[-0.04em]"

  defp button_size_class("default"), do: "min-h-target-min px-[18px] text-sm"
  defp button_size_class("large"), do: "min-h-12 px-[18px] text-[15px]"

  defp button_variant_class("dark"), do: "border-0 bg-ink font-semibold text-white hover:bg-slate"
  defp button_variant_class("lime"), do: "border-0 bg-accent font-semibold text-ink hover:brightness-105"

  defp button_variant_class("outline"),
    do: "border border-app-line-strong bg-transparent font-medium text-on-app hover:bg-app-raised"

  defp button_variant_class("ghost"), do: "border-0 bg-transparent font-medium text-on-app-muted hover:text-on-app"

  defp sidebar_variant_class("action"), do: "border border-app-line-strong font-semibold"
  defp sidebar_variant_class("link"), do: "border border-transparent font-medium"

  defp chip_variant_class("dashed"),
    do:
      "border border-dashed border-app-line-strong bg-transparent px-3 font-medium text-on-app-2 hover:border-on-app-muted hover:text-on-app"

  defp chip_variant_class("outline"),
    do: "border border-app-line-strong bg-transparent px-3.5 text-on-app-2 hover:bg-app-raised hover:text-on-app"

  defp prompt_box_surface_class("light"), do: "border-[1.5px] border-ink bg-white shadow-prompt"
  defp prompt_box_surface_class("app"), do: "border border-app-line-strong bg-app-raised"
end
