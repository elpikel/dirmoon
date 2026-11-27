defmodule DirmoonWeb.PageHTML do
  @moduledoc """
  The landing page rendered by `DirmoonWeb.PageController`, and its two
  sign-up forms, `:hero` and `:closing`, also re-rendered by
  `DirmoonWeb.SignUpController` when a sign-up fails. The landing page shows
  no flash notices: what a form has to say is shown in the form.

  The landing page is in English, like the whole app (the audience is
  global). Its example is a real research (Run 9 in the owner's dev
  database, 24 Nov 2026, market Poland) with the Niche names translated:
  every figure in it is what the keyword API returned, none is invented.

  The section for an owner who already has a website lists, in the
  report's order, what the Site Scan tells them. It quotes no figure: there
  is no real scan to quote.

  See the `page_html` directory for all templates available.
  """
  use DirmoonWeb, :html

  alias Dirmoon.SiteScans

  embed_templates "page_html/*"

  @sign_up_form_names [:hero, :closing]

  @example %{
    best_niche_typed_per_month: "1,090",
    best_niche_typed_per_day: "36",
    best_niche_click_price: "$6.79",
    best_niche_score: "7.7"
  }

  @site_scan_findings [
    "Which topics people search for that your site has no page for",
    "Whether Google can find and read your pages",
    "Whether each page says clearly what it offers",
    "Whether it loads fast and works on a phone",
    "Whether Google can see you are a real business"
  ]

  @page_title "Validate your business idea with Google search data"
  @meta_description "Niche finder: test a business idea with real monthly search volume and keyword competition. " <>
                      "Or paste your site and get a plain-English list of what to fix."

  @doc """
  Returns the assigns the landing page template needs: the given sign-up
  forms, the page title and what search engines and link previews read (the
  description, the page's one address, the structured data).
  """
  def landing_assigns(sign_up_forms) do
    [
      sign_up_forms: sign_up_forms,
      page_title: @page_title,
      meta_description: @meta_description,
      canonical_url: url(~p"/"),
      share_image_alt: "dirmoon: validate your business idea before you build it.",
      structured_data: structured_data()
    ]
  end

  # What the landing page tells search engines it is: the site and who runs
  # it. Only what the page itself says; no price, rating or address.
  defp structured_data do
    home = url(~p"/")

    %{
      "@context" => "https://schema.org",
      "@graph" => [
        %{
          "@type" => "WebSite",
          "@id" => home <> "#website",
          "url" => home,
          "name" => "dirmoon",
          "description" => @meta_description,
          "inLanguage" => "en",
          "publisher" => %{"@id" => home <> "#organization"}
        },
        %{
          "@type" => "Organization",
          "@id" => home <> "#organization",
          "url" => home,
          "name" => "dirmoon",
          "logo" => url(~p"/apple-touch-icon.png")
        }
      ]
    }
  end

  @doc """
  Returns an empty form for each landing sign-up form, keyed by its name.
  """
  def sign_up_forms do
    Map.new(@sign_up_form_names, &{&1, to_form(%{}, as: :user)})
  end

  @doc """
  Returns the landing sign-up forms with the submitted one filled in again
  and the given message under its email field, so only that form shows the
  submitted email and what went wrong.
  """
  def sign_up_forms(submitted_form_name, user_params, email_error) when submitted_form_name in @sign_up_form_names do
    Map.put(sign_up_forms(), submitted_form_name, to_form(user_params, as: :user, errors: [email: {email_error, []}]))
  end

  @doc """
  Returns the sign-up form named by the hidden `form` field, the hero form
  when it names none.
  """
  def submitted_sign_up_form_name("closing"), do: :closing
  def submitted_sign_up_form_name(_form_field), do: :hero

  @doc """
  Returns the landing page path that scrolls to the given sign-up form's
  section.
  """
  def sign_up_form_path(:hero), do: ~p"/"
  def sign_up_form_path(:closing), do: ~p"/" <> "#closing"

  @doc """
  Returns the confirmation shown after a sign-up, identical for new emails and
  emails that already have a User.
  """
  def sign_up_confirmation_message(email), do: "We sent a sign-in link to #{email}. Check your inbox."

  attr :name, :atom, required: true, values: @sign_up_form_names
  attr :form, Phoenix.HTML.Form, required: true
  attr :confirmation, :string, default: nil, doc: "shown in place of the form after a sign-up"

  defp sign_up_form(%{confirmation: confirmation} = assigns) when is_binary(confirmation) do
    ~H"""
    <.prompt_box
      id={"sign-up-confirmation-#{@name}"}
      role="status"
      class="flex w-full max-w-[640px] items-center justify-center gap-3 px-6 py-5 text-[17px] font-medium text-ink"
    >
      <.icon name="hero-envelope" class="size-5 shrink-0" />
      <span>{@confirmation}</span>
    </.prompt_box>
    """
  end

  defp sign_up_form(assigns) do
    assigns = assign(assigns, :email_input_id, "sign-up-#{assigns.name}-email")

    ~H"""
    <.form
      for={@form}
      id={"sign-up-form-#{@name}"}
      action={~p"/sign-up"}
      method="post"
      class="flex w-full max-w-[640px] flex-col items-center gap-4 text-left"
    >
      <input type="hidden" name="form" value={@name} />
      <.prompt_box class={[
        "flex w-full items-center gap-2 p-2 pl-4 sm:gap-3 sm:p-3 sm:pl-5",
        "has-[input:focus-visible]:outline-2 has-[input:focus-visible]:outline-offset-4 has-[input:focus-visible]:outline-ink"
      ]}>
        <label for={@email_input_id} class="sr-only">Email address</label>
        <div class="min-w-0 flex-1 *:mb-0">
          <.input
            field={@form[:email]}
            id={@email_input_id}
            type="email"
            placeholder="you@company.com"
            autocomplete="email"
            spellcheck="false"
            required
            class="min-h-11 w-full border-0 bg-transparent p-0 text-[16px] font-medium sm:min-h-12 sm:text-[19px] tracking-[-0.01em] text-ink placeholder:text-body-muted focus-visible:outline-none"
          />
        </div>
        <.button
          variant="dark"
          size="large"
          type="submit"
          class="flex-none max-sm:min-h-11 max-sm:px-3.5"
        >
          Create account
        </.button>
      </.prompt_box>
      <p class="text-[13px] text-body-muted">We'll email you a sign-in link. No password.</p>
    </.form>
    """
  end

  attr :id, :string, required: true

  defp journey(assigns) do
    assigns = assign(assigns, :example, @example)

    ~H"""
    <div id={@id} class="relative mx-auto w-full max-w-[760px] text-left">
      <div
        data-part="flight-path"
        aria-hidden="true"
        class="pointer-events-none absolute inset-y-0 left-0 w-14 max-sm:hidden"
      >
        <div class="absolute inset-y-0 left-1/2 -translate-x-1/2 border-l-[3px] border-dotted border-accent">
        </div>
      </div>

      <ol class="m-0 flex list-none flex-col gap-12 p-0 pb-4 sm:gap-20 sm:pl-[88px]">
        <.journey_stop
          id={"#{@id}-launch"}
          number="01"
          marker="launch"
          title="How do I validate my business idea?"
        >
          <:lead>
            Describe it in one sentence. dirmoon checks it against what people really search for on Google.
          </:lead>
        </.journey_stop>

        <.journey_stop
          id={"#{@id}-demand"}
          number="02"
          title="How do I know if people are searching for my business idea?"
        >
          <:lead>
            dirmoon shows how many times a month people type it into Google. In the example, people look for skate rental <strong class="font-semibold text-ink">{@example.best_niche_typed_per_month} times a month</strong>: about {@example.best_niche_typed_per_day} times a day.
          </:lead>
        </.journey_stop>

        <.journey_stop
          id={"#{@id}-click-price"}
          number="03"
          title="What would a Google Ads click cost for my idea?"
        >
          <:lead>
            dirmoon shows what businesses pay Google for one ad click. For skate rental it is <strong class="font-semibold text-ink">{@example.best_niche_click_price}</strong>. A high price means a customer is worth money.
          </:lead>
        </.journey_stop>

        <.journey_stop
          id={"#{@id}-competition"}
          number="04"
          title="Who is on the first page of Google, and is the competition too strong?"
        >
          <:lead>
            dirmoon lists every site on Google's first page and tells you how hard it is to get there. For skate rental: businesses like yours and big portals, so it will be a fight.
          </:lead>
        </.journey_stop>

        <.journey_stop
          id={"#{@id}-competitor-prices"}
          number="05"
          title="What do my competitors charge?"
        >
          <:lead>
            Ask, and dirmoon opens your competitors' pages and lists the prices they publish, each with a link.
          </:lead>
        </.journey_stop>

        <.journey_stop
          id={"#{@id}-arrival"}
          number="06"
          marker="arrival"
          title="What are my chances of a successful business?"
        >
          <:lead>
            dirmoon gives your idea a score from 0 to 10 and a plain verdict: worth a try, worth it but hard, or probably not worth it. Skate rental scored <strong class="font-semibold text-ink">{@example.best_niche_score} out of 10</strong>: worth it, but hard.
          </:lead>
          <p data-part="decision" class="m-0 max-w-[640px] text-[17px] leading-normal text-body">
            Then dirmoon writes the plan and the text for your page, ready to hand to whoever builds your site.
          </p>
        </.journey_stop>
      </ol>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :number, :string, required: true
  attr :title, :string, required: true

  attr :marker, :string,
    default: "question",
    values: ~w(launch question arrival),
    doc: "launch is the launch pad, arrival the destination flag, question every stop between"

  slot :lead, required: true
  slot :inner_block

  defp journey_stop(assigns) do
    ~H"""
    <li id={@id} data-part="step" class="flex flex-col gap-4">
      <div class="flex flex-col gap-3">
        <div class="relative">
          <.journey_marker number={@number} kind={@marker} />
          <h3 class="m-0 text-[clamp(22px,2.4vw,30px)] leading-[1.1] font-extrabold tracking-[-0.03em] text-balance text-ink">
            {@title}
          </h3>
        </div>
        <p
          data-part="lead"
          class="m-0 max-w-[640px] text-[16px] leading-normal text-body sm:text-[17px]"
        >
          {render_slot(@lead)}
        </p>
      </div>
      {render_slot(@inner_block)}
    </li>
    """
  end

  attr :number, :string, required: true
  attr :kind, :string, required: true

  defp journey_marker(assigns) do
    ~H"""
    <div
      data-part="marker"
      data-marker={@kind}
      class="mb-3 flex sm:absolute sm:-top-1 sm:-left-[88px] sm:mb-0 sm:w-14 sm:justify-center"
    >
      <span
        data-part="number"
        class={[
          "flex size-9 items-center justify-center rounded-pill font-mono text-xs font-semibold tracking-[0.05em]",
          marker_class(@kind)
        ]}
      >
        {@number}
      </span>
    </div>
    """
  end

  attr :id, :string, required: true

  defp site_scan_section(assigns) do
    assigns = assign(assigns, page_limit: SiteScans.page_limit(), findings: @site_scan_findings)

    ~H"""
    <div class="flex w-full flex-col items-center gap-10">
      <p
        data-part="intro"
        class="m-0 max-w-[680px] text-[17px] leading-normal text-pretty text-body"
      >
        dirmoon reads up to {@page_limit} pages of your site and tells you in plain words what to fix first.
      </p>

      <div class="flex w-full max-w-[880px] flex-col gap-4 text-left">
        <span
          data-part="findings-lead"
          class="font-mono text-xs uppercase tracking-[0.1em] text-body-muted"
        >
          It tells you:
        </span>
        <ul
          id={"#{@id}-findings"}
          class="m-0 grid list-none gap-3 p-0 sm:grid-cols-2 lg:grid-cols-3"
        >
          <li
            :for={finding <- @findings}
            data-part="finding"
            class="flex items-start gap-3 rounded-tile border border-line bg-white px-5 py-4"
          >
            <.icon name="hero-check-circle" class="mt-0.5 size-5 shrink-0 text-ink" />
            <span class="text-[16px] leading-snug font-semibold text-ink">{finding}</span>
          </li>
        </ul>
      </div>

      <p
        id={"#{@id}-next"}
        class="m-0 max-w-[680px] text-[17px] leading-normal text-pretty text-body"
      >
        A topic with no page? Ask for its brief: the plan and the text for that page. dirmoon also sets your page beside your competitors' pages.
      </p>
    </div>
    """
  end

  defp marker_class("question"), do: "border-2 border-accent bg-ink text-accent"
  defp marker_class(_launch_or_arrival), do: "bg-accent text-ink ring-2 ring-ink"
end
