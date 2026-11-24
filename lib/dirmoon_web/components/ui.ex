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

  @crescent_path "M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"
  @underline_path "M4 14 C 120 4, 240 22, 360 12 S 540 6, 596 12"

  @doc """
  Renders the crescent moon mark, inline as SVG. Placeholder quality: the owner
  has not approved a logo.

      <.moon_mark />
      <.moon_mark tone="accent" size={14} />
      <.moon_mark label="dirmoon" />
  """
  attr :tone, :string, default: "ink", values: ~w(ink accent), doc: "ink on light, accent on slate"
  attr :size, :integer, default: 24, doc: "width and height in pixels"
  attr :label, :string, default: nil, doc: "accessible name; the mark is decorative when nil"
  attr :class, :any, default: nil
  attr :rest, :global

  def moon_mark(assigns) do
    assigns = assign(assigns, :path, @crescent_path)

    ~H"""
    <svg
      data-moon-mark
      viewBox="0 0 24 24"
      width={@size}
      height={@size}
      role={@label && "img"}
      aria-label={@label}
      aria-hidden={is_nil(@label) && "true"}
      class={["flex-none", @class]}
      {@rest}
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
  Renders the floating nav card: the moon mark and "dirmoon" on the left, the
  inner block (nav links and a dark button) on the right. It wraps onto two
  rows on narrow screens.

      <.nav_card id="app-nav" home_href="/app/research/new">
        <.nav_link href="/app/runs" active>Wyniki</.nav_link>
        <.button variant="dark" href="/app/research/new">Nowy research</.button>
      </.nav_card>
  """
  attr :id, :string, default: nil
  attr :home_href, :string, default: "/", doc: "where the mark and wordmark link to"
  attr :label, :string, default: "Główna", doc: "accessible name of the nav"
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def nav_card(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "mx-auto flex w-full max-w-content flex-wrap items-center justify-between gap-x-6 gap-y-2",
        "rounded-nav border border-line bg-page py-2.5 pr-3 pl-[22px] shadow-nav max-sm:pl-4",
        @class
      ]}
      {@rest}
    >
      <.wordmark href={@home_href} />
      <nav
        aria-label={@label}
        class="flex flex-wrap items-center gap-x-7 gap-y-2 text-sm font-medium max-sm:gap-x-5"
      >
        {render_slot(@inner_block)}
      </nav>
    </div>
    """
  end

  @doc """
  Renders a text link for the nav card. The active link is the current page.

      <.nav_link href="/app/runs" active>Wyniki</.nav_link>
  """
  attr :active, :boolean, default: false, doc: "marks the current page"
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(href navigate patch method replace)
  slot :inner_block, required: true

  def nav_link(assigns) do
    ~H"""
    <.link
      aria-current={@active && "page"}
      class={[
        "inline-flex min-h-target-min items-center no-underline transition-colors duration-150",
        if(@active, do: "font-bold text-ink", else: "text-body-muted hover:text-ink"),
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
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def eyebrow(assigns) do
    ~H"""
    <span
      class={[
        "rounded-chip bg-chip px-3 py-[7px] font-mono text-xs uppercase tracking-[0.1em] text-ink",
        @class
      ]}
      {@rest}
    >{render_slot(@inner_block)}</span>
    """
  end

  @doc """
  Renders a page headline: Inter 800, tight tracking, line height about 1.
  The `underline` slot holds the one phrase that carries the lime hand-drawn
  underline; it is rendered after the inner block.

      <.headline>
        Zanim zbudujesz, sprawdź,
        <:underline>czy ktoś tego szuka.</:underline>
      </.headline>

      <.headline size="page">Research <:underline>w toku.</:underline></.headline>
  """
  attr :level, :string, default: "h1", values: ~w(h1 h2), doc: "the heading element"

  attr :size, :string,
    default: "page",
    values: ~w(hero page),
    doc: "hero is the new-research headline (up to 84px), page is the other screens (up to 64px)"

  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block
  slot :underline, doc: "the phrase drawn over the lime underline"

  def headline(assigns) do
    assigns = assign(assigns, :underline_path, @underline_path)

    ~H"""
    <.dynamic_tag
      tag_name={@level}
      class={[
        "relative isolate m-0 font-extrabold text-balance",
        headline_size_class(@size),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
      <span :if={@underline != []} data-part="underline" class="relative inline-block">
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
  Renders the dark slate panel that holds the tool: a mono top bar with
  `dirmoon / <context>` on the left and an optional note on the right, an
  optional status row on slate-raised with the moon mark and one first-person
  sentence, then the inner block.

      <.dark_panel context="wynajem kamperów" note="Dane przykładowe">
        <:status>Sprawdzam, kto odpowiada na najlepsze frazy.</:status>
        ...
      </.dark_panel>
  """
  attr :id, :string, default: nil
  attr :context, :string, required: true, doc: "shown as `dirmoon / <context>` in the top bar"
  attr :note, :string, default: nil, doc: "short mono note at the right of the top bar"
  attr :class, :any, default: nil
  attr :rest, :global
  slot :status, doc: "one first-person sentence saying what the tool found or is doing"
  slot :inner_block, required: true

  def dark_panel(assigns) do
    ~H"""
    <section
      id={@id}
      data-surface="dark"
      class={[
        "w-full overflow-hidden rounded-panel bg-slate text-left text-on-slate shadow-panel",
        @class
      ]}
      {@rest}
    >
      <div
        data-part="top-bar"
        class="flex flex-wrap items-center justify-between gap-3 border-b border-slate-line px-5 py-3.5 font-mono"
      >
        <div class="flex items-center gap-2.5 text-xs text-on-slate-muted">
          <.moon_mark tone="accent" size={14} />
          <span data-part="context">dirmoon / {@context}</span>
        </div>
        <span :if={@note} data-part="note" class="text-[11px] text-on-slate-muted">{@note}</span>
      </div>
      <div
        :if={@status != []}
        data-part="status"
        role="status"
        class="flex items-center gap-3 border-b border-slate-line bg-slate-raised px-5 py-3.5"
      >
        <.moon_mark tone="accent" size={26} />
        <span class="text-[15px] font-medium">{render_slot(@status)}</span>
      </div>
      {render_slot(@inner_block)}
    </section>
    """
  end

  @doc """
  Renders a button, or a link styled as a button when given `href`,
  `navigate` or `patch`. Always at least 44px tall.

  Variants: `dark` (ink fill, on light), `lime` (the one primary action on
  slate), `outline` (on slate) and `ghost` (text only, on slate).

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

  attr :rest, :global, include: ~w(href navigate patch method download name value disabled form replace target rel)

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

    if rest[:href] || rest[:navigate] || rest[:patch] do
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
  Renders a 36px pill chip as a button, as in the prompt box footer.

  Variants: `dark` (ink fill, the mode chip), `light` (white with a border,
  country and city), `dashed` (optional fields, "+ Domena") and `soft` (page
  fill, the example prompts).

      <.chip variant="dark" phx-click="toggle_mode">Nowy pomysł</.chip>
      <.chip variant="dashed" phx-click="add_domain">+ Domena</.chip>
  """
  attr :variant, :string, default: "light", values: ~w(dark light dashed soft)
  attr :type, :string, default: "button"
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(name value disabled form)
  slot :inner_block, required: true

  def chip(assigns) do
    ~H"""
    <button
      type={@type}
      data-variant={@variant}
      class={[
        "inline-flex min-h-9 cursor-pointer items-center gap-1.5 rounded-pill font-sans text-[13px]",
        "transition-colors duration-150",
        chip_variant_class(@variant),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Renders the white prompt box: a 1.5px ink border, radius 22 and the lime
  edge under it. The inner block lays out its content.

      <.prompt_box class="flex flex-col">...</.prompt_box>
  """
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def prompt_box(assigns) do
    ~H"""
    <div
      class={["rounded-prompt border-[1.5px] border-ink bg-white text-left shadow-prompt", @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders the dark "jak to działa" panel: the nine Steps summed up in four
  stages (01–02 Frazy, 03–04 Popyt, 05–07 Konkurencja, 08–09 Strona), with
  its caption below. Shared by the landing and the new research screen.

      <.how_it_works id="how-it-works" class="mt-20" />
  """
  attr :id, :string, default: "how-it-works"
  attr :class, :any, default: nil

  def how_it_works(assigns) do
    assigns = assign(assigns, :stages, how_it_works_stages())

    ~H"""
    <figure class={["m-0 flex w-full flex-col items-center gap-4", @class]}>
      <.dark_panel
        id={@id}
        context="jak to działa"
        note="9 kroków, jedna decyzja po Twojej stronie"
      >
        <ol class="m-0 grid list-none grid-cols-[repeat(auto-fit,minmax(min(240px,100%),1fr))] p-0">
          <li
            :for={stage <- @stages}
            class="flex flex-col gap-2.5 border-r border-b border-slate-line px-6 pt-6 pb-7 last:border-r-0"
          >
            <span data-part="stage-steps" class="font-mono text-xs text-accent">{stage.steps}</span>
            <span data-part="stage-name" class="text-xl font-bold tracking-[-0.01em]">
              {stage.name}
            </span>
            <p class="m-0 text-[15px] leading-[1.55] text-on-slate-2">{stage.summary}</p>
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
  Renders a stat tile on slate: a small label above a large value.
  `highlight` draws the value in the accent.

      <.stat_tile label="Wyszukiwania / mies." value={@volume} />
      <.stat_tile label="Wypożyczalnie w top 10" value="0" highlight />
  """
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :highlight, :boolean, default: false
  attr :class, :any, default: nil
  attr :rest, :global

  def stat_tile(assigns) do
    ~H"""
    <div
      class={[
        "flex flex-col gap-1.5 rounded-tile border border-slate-line-strong bg-slate-raised px-4 py-3.5",
        @class
      ]}
      {@rest}
    >
      <span data-part="label" class="text-xs text-on-slate-2">{@label}</span>
      <span
        data-part="value"
        class={[
          "text-[26px] font-extrabold tracking-[-0.03em]",
          if(@highlight, do: "text-accent", else: "text-on-slate")
        ]}
      >{@value}</span>
    </div>
    """
  end

  @doc """
  Renders the note on slate that the research is stopped and must be resumed
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
    <p id={@id} class={["m-0 text-[15px] leading-normal text-on-slate-2", @class]}>
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

  defp how_it_works_stages do
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
    do: "border border-slate-line-strong bg-transparent font-medium text-on-slate hover:bg-slate-raised"

  defp button_variant_class("ghost"), do: "border-0 bg-transparent font-medium text-on-slate-muted hover:text-on-slate"

  defp chip_variant_class("dark"), do: "border-0 bg-ink px-3 font-medium text-white hover:bg-slate"

  defp chip_variant_class("light"), do: "border border-line-strong bg-white px-3 font-medium text-ink hover:border-ink"

  defp chip_variant_class("dashed"),
    do: "border border-dashed border-line-dashed bg-transparent px-3 font-medium text-body-muted hover:text-ink"

  defp chip_variant_class("soft"), do: "border border-line-strong bg-page px-3.5 text-body hover:bg-white"
end
