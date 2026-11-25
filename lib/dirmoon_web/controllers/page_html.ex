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

  See the `page_html` directory for all templates available.
  """
  use DirmoonWeb, :html

  embed_templates "page_html/*"

  @sign_up_form_names [:hero, :closing]

  @example %{
    description: "Ice skate rental",
    city: "Gdańsk, Poland",
    niche_count: 7,
    low_niche_count: 5,
    other_niche_count: 4,
    niches: [
      %{
        name: "Skate rental",
        verdict: :hard,
        score: "7.7",
        figures: "1,090 searches a month · $6.79 per ad click",
        first_page: "On page one today: businesses like yours and big portals."
      },
      %{
        name: "Ice rinks with skate rental",
        verdict: :hard,
        score: "5.6",
        figures: "40 searches a month · $4.10 per ad click",
        first_page: "On page one today: businesses like yours, guides and blogs."
      },
      %{
        name: "Skates for kids",
        verdict: :low,
        score: "2.3",
        figures: "No measurable searches · nobody pays for ads",
        first_page: "On page one today: business directories and big portals."
      }
    ]
  }

  @verdict_labels %{hard: "Worth it, but hard", low: "Probably not worth it"}
  @verdict_classes %{hard: "text-warn", low: "text-on-slate-muted"}

  @sources [
    %{
      question: "Where do the numbers come from?",
      answer:
        "From Google's own keyword and search results data. dirmoon looks up what people actually type about your idea, how often each phrase is searched, what an ad click costs and who holds the first page today."
    },
    %{
      question: "Does an AI make any of it up?",
      answer:
        "No. The AI only suggests where to look and sorts what was found into niches. Every phrase and every number comes from Google's data, never from an AI's guess."
    }
  ]

  @answers [
    %{
      question: "Do people search for this at all, and how many of them?",
      answer:
        "Yes, but mostly in one way: \"skate rental\" gets 1,090 searches a month. The other niches get 40 or fewer, and several get none that Google can measure."
    },
    %{
      question: "Is a customer here worth real money?",
      answer:
        "Businesses pay Google $6.79 for a single click on an ad for skate rental. Nobody pays for the low-demand niches. The higher the click price, the more a customer is worth."
    },
    %{
      question: "Who is already there, and can I get past them?",
      answer:
        "Page one is held by businesses like yours and big portals, so it will be a fight. The report lists every site on page one, with a link to each and what kind of site it is."
    },
    %{
      question: "What do my competitors charge?",
      answer:
        "Ask for it on any niche: dirmoon opens the competitors' pages and lists the prices they publish, each with a link to the page it came from. It never guesses a price that is not written there."
    }
  ]

  @doc """
  Returns the assigns the landing page template needs: the given sign-up
  forms and the page title.
  """
  def landing_assigns(sign_up_forms) do
    [sign_up_forms: sign_up_forms, page_title: "Check demand before you build"]
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
        "flex w-full flex-wrap items-start gap-3 p-3 pl-5 max-sm:pl-4",
        "has-[input:focus-visible]:outline-2 has-[input:focus-visible]:outline-offset-4 has-[input:focus-visible]:outline-ink"
      ]}>
        <label for={@email_input_id} class="sr-only">Email address</label>
        <div class="min-w-0 flex-[1_1_240px] *:mb-0">
          <.input
            field={@form[:email]}
            id={@email_input_id}
            type="email"
            placeholder="you@company.com"
            autocomplete="email"
            spellcheck="false"
            required
            class="min-h-12 w-full border-0 bg-transparent p-0 text-[19px] font-medium tracking-[-0.01em] text-ink placeholder:text-body-muted focus-visible:outline-none"
          />
        </div>
        <.button variant="dark" size="large" type="submit" class="flex-none max-sm:w-full">
          Create account
        </.button>
      </.prompt_box>
      <p class="text-[13px] text-body-muted">We'll email you a sign-in link. No password.</p>
    </.form>
    """
  end

  attr :id, :string, required: true

  defp journey(assigns) do
    assigns =
      assign(assigns,
        example: @example,
        verdict_labels: @verdict_labels,
        verdict_classes: @verdict_classes,
        answers: @answers,
        sources: @sources
      )

    ~H"""
    <div
      id={@id}
      class="grid w-full grid-cols-[36px_minmax(0,1fr)] gap-x-4 text-left sm:grid-cols-[56px_minmax(0,1fr)] sm:gap-x-8"
    >
      <div data-part="flight-path" aria-hidden="true" class="relative">
        <div class="absolute inset-y-0 left-1/2 -translate-x-1/2 border-l-[3px] border-dotted border-accent">
        </div>
        <div class="sticky top-[40vh] flex justify-center">
          <.rocket class="size-9 rotate-180 sm:size-12" />
        </div>
      </div>

      <ol class="m-0 flex list-none flex-col gap-20 p-0 pb-4">
        <.journey_step id={"#{@id}-idea"} number="01" title="You start with a question">
          <:lead>
            You want to open a business or add a service, and you are about to put time and money into it. First you need to know whether anyone is looking for it. Describe the idea in one sentence. No keyword lists, no SEO knowledge.
          </:lead>
          <blockquote
            data-part="example-idea"
            class="m-0 flex flex-col gap-3 border-l-[3px] border-accent pl-5"
          >
            <p
              data-part="description"
              class="m-0 text-[clamp(24px,2.8vw,34px)] leading-tight font-extrabold tracking-[-0.03em] text-ink"
            >
              “{@example.description}”
            </p>
            <span
              data-part="city"
              class="inline-flex items-center gap-1.5 font-mono text-[13px] text-body-muted"
            >
              <.icon name="hero-map-pin" class="size-4" />{@example.city}
            </span>
          </blockquote>
          <div class="flex flex-col gap-3">
            <span class="font-mono text-xs uppercase tracking-[0.1em] text-body-muted">What you want to know</span>
            <ul
              data-part="questions"
              class="m-0 flex list-none flex-col gap-2 p-0 text-[17px] leading-normal text-ink"
            >
              <li :for={entry <- @answers} class="flex items-start gap-2.5">
                <.icon name="hero-question-mark-circle" class="mt-1 size-5 shrink-0 text-body-muted" />
                <span>{entry.question}</span>
              </li>
            </ul>
          </div>
        </.journey_step>

        <.journey_step id={"#{@id}-research"} number="02" title="dirmoon checks real search data">
          <:lead>
            You wait while dirmoon does the looking up. It does not guess.
          </:lead>
          <dl id={"#{@id}-sources"} class="m-0 flex flex-col gap-6">
            <div
              :for={entry <- @sources}
              data-part="source"
              class="flex flex-col gap-1.5 border-l-2 border-accent pl-4"
            >
              <dt class="text-[17px] font-bold tracking-[-0.01em] text-ink">{entry.question}</dt>
              <dd class="m-0 max-w-[720px] text-[16px] leading-[1.55] text-body">{entry.answer}</dd>
            </div>
          </dl>
        </.journey_step>

        <.journey_step id={"#{@id}-report"} number="03" title="You get a ranked report">
          <:lead>
            The phrases are grouped into niches, the best one first. Each niche gets a verdict in plain words and the numbers behind it. Together they answer the questions you came with.
          </:lead>
          <figure class="m-0 flex flex-col gap-3">
            <.dark_panel
              id={"#{@id}-report-panel"}
              context={String.downcase(@example.description)}
              note={"#{@example.niche_count} niches"}
            >
              <ol class="m-0 flex list-none flex-col divide-y divide-slate-line p-0">
                <li
                  :for={niche <- @example.niches}
                  data-part="niche"
                  class="flex flex-col gap-2 px-5 py-5 sm:px-6"
                >
                  <div class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
                    <span data-part="name" class="text-[17px] font-bold tracking-[-0.01em]">{niche.name}</span>
                    <span
                      data-part="verdict"
                      class={["text-sm font-semibold", Map.fetch!(@verdict_classes, niche.verdict)]}
                    >
                      {Map.fetch!(@verdict_labels, niche.verdict)} · {niche.score}/10
                    </span>
                  </div>
                  <span data-part="figures" class="font-mono text-[13px] text-on-slate-2">{niche.figures}</span>
                  <span data-part="first-page" class="text-sm text-on-slate-muted">{niche.first_page}</span>
                </li>
                <li data-part="more" class="px-5 py-4 text-sm text-on-slate-muted sm:px-6">
                  And {@example.other_niche_count} more niches, ranked the same way.
                </li>
              </ol>
            </.dark_panel>
            <figcaption class="font-mono text-xs leading-relaxed text-body-muted">
              A real research from 24 Nov 2026. Market: Poland, names translated from Polish.
            </figcaption>
          </figure>
          <dl id={"#{@id}-answers"} class="m-0 flex flex-col gap-6">
            <div
              :for={entry <- @answers}
              data-part="answer"
              class="flex flex-col gap-1.5 border-l-2 border-accent pl-4"
            >
              <dt class="text-[17px] font-bold tracking-[-0.01em] text-ink">{entry.question}</dt>
              <dd class="m-0 max-w-[720px] text-[16px] leading-[1.55] text-body">{entry.answer}</dd>
            </div>
          </dl>
        </.journey_step>

        <.journey_step id={"#{@id}-value"} number="04" title="You decide with numbers, not hope">
          <:lead>
            Here {@example.low_niche_count} of {@example.niche_count} niches turned out not worth a page, and the best one will be a fight. That is cheaper to learn now than after you build.
          </:lead>
          <p class="m-0 max-w-[640px] text-[17px] leading-normal text-body">
            Pick the niche you want and dirmoon writes its brief: the plan and the text for one page about that niche, with the title, headings, sections and the phrases to cover. You hand it to whoever builds your site.
          </p>
        </.journey_step>
      </ol>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :number, :string, required: true
  attr :title, :string, required: true
  slot :lead, required: true
  slot :inner_block, required: true

  defp journey_step(assigns) do
    ~H"""
    <li id={@id} data-part="step" class="flex flex-col gap-5">
      <div class="flex flex-col gap-3">
        <span
          data-part="number"
          class="self-start rounded-chip bg-ink px-2.5 py-1 font-mono text-xs tracking-[0.1em] text-accent"
        >
          {@number}
        </span>
        <h3 class="m-0 text-[clamp(22px,2.4vw,30px)] leading-[1.1] font-extrabold tracking-[-0.03em] text-ink">
          {@title}
        </h3>
        <p class="m-0 max-w-[640px] text-[17px] leading-normal text-body">{render_slot(@lead)}</p>
      </div>
      {render_slot(@inner_block)}
    </li>
    """
  end
end
