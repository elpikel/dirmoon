defmodule DirmoonWeb.BillingLive do
  @moduledoc """
  The plan screen, "Plan" (`/app/billing`, ADR-0004): the researches the
  Account has left, its monthly plan's state, and the two ways to pay from
  `Dirmoon.Billing.offer/0`, worded by `DirmoonWeb.OfferDisplay` (as on the
  landing page), each a plain form posting to
  `DirmoonWeb.BillingController`, which sends the User on to Stripe. With a
  running plan the monthly option has no button; "Manage plan" (Stripe's
  customer portal) shows whenever the Account has a plan, which only an
  Account with a Stripe Customer can have. An Account with Unpaid Access is
  told it needs no plan and can still pay.

  Stripe sends the User back with `?paid=1`, which grants nothing. The screen
  listens for the Account's billing updates (`Dirmoon.Billing.subscribe/1`)
  and re-reads on each. With no research left when the screen opened, the
  payment can't have been counted yet: it says the payment is being
  confirmed. With researches already left it can't tell, so it says the
  payment is counted once Stripe confirms it. Either way it says the payment
  was received only once an update has raised the researches left above what
  they were when the screen opened.
  """
  use DirmoonWeb, :live_view

  alias Dirmoon.Billing
  alias Dirmoon.Billing.Subscription
  alias Dirmoon.Format
  alias DirmoonWeb.OfferDisplay

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:billing} context="plan">
      <:status>
        <span id="billing-status-line">{status_sentence(
          @researches_left,
          @payment_notice,
          running_plan?(@subscription)
        )}</span>
      </:status>
      <section id="billing-screen" class="flex flex-col gap-5 px-7 pt-6 pb-8 max-sm:px-4">
        <h1 class="sr-only">Plan</h1>
        <.payment_notice :if={@payment_notice} notice={@payment_notice} />

        <div
          id="plan-state-card"
          class="flex max-w-[900px] flex-wrap items-center gap-x-5 gap-y-3 rounded-tile border border-app-line-strong bg-app-raised px-5 py-4"
        >
          <p
            id="plan-state"
            data-problem={@plan_state.problem?}
            class="m-0 flex min-w-0 flex-[1_1_280px] items-start gap-2.5 text-[15px] leading-normal text-on-app"
          >
            <.icon
              :if={@plan_state.problem?}
              name="hero-exclamation-circle"
              class="mt-0.5 size-5 shrink-0 text-warn"
            />
            <span>{@plan_state.sentence}</span>
          </p>
          <.form
            :if={@subscription}
            for={%{}}
            id="manage-plan"
            action={~p"/app/billing/portal"}
            class="flex-none max-sm:w-full"
          >
            <.button variant="outline" type="submit" class="max-sm:w-full">
              Manage plan <.icon name="hero-arrow-top-right-on-square-mini" class="size-4" />
            </.button>
          </.form>
        </div>

        <div id="billing-options" class="grid max-w-[900px] gap-4 min-[720px]:grid-cols-2">
          <.payment_option
            id="single-research"
            option={OfferDisplay.single_research(@offer)}
            research_includes={OfferDisplay.research_includes(@offer)}
          >
            <:action>
              <.checkout_form
                id="single-research-checkout"
                product="single_research"
                variant="outline"
              >
                Buy one research
              </.checkout_form>
            </:action>
          </.payment_option>

          <.payment_option
            id="monthly-plan"
            option={OfferDisplay.monthly_plan(@offer)}
            research_includes={OfferDisplay.research_includes(@offer)}
          >
            <:action>
              <.checkout_form
                :if={!running_plan?(@subscription)}
                id="monthly-plan-checkout"
                product="subscription"
                variant="lime"
              >
                Start the monthly plan
              </.checkout_form>
              <p
                :if={running_plan?(@subscription)}
                id="monthly-plan-current"
                class="m-0 flex min-h-target-min items-center gap-2 text-sm font-medium text-on-app-2"
              >
                <.icon name="hero-check-circle" class="size-5 shrink-0 text-accent" />
                This is your plan.
              </p>
            </:action>
          </.payment_option>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    scope = socket.assigns.current_scope

    if connected?(socket), do: Billing.subscribe(scope)

    researches_left = Billing.researches_left(scope)
    payment_return? = params["paid"] == "1"

    {:ok,
     socket
     |> assign(
       page_title: "Plan",
       offer: Billing.offer(),
       payment_return?: payment_return?,
       researches_left_at_mount: researches_left,
       payment_notice: notice_at_mount(payment_return?, researches_left)
     )
     |> assign_billing(researches_left, Billing.subscription(scope))}
  end

  @impl true
  def handle_info({:billing_updated, _account_id}, socket) do
    scope = socket.assigns.current_scope
    researches_left = Billing.researches_left(scope)

    {:noreply,
     socket
     |> assign(:payment_notice, notice_after_update(socket.assigns, researches_left))
     |> assign_billing(researches_left, Billing.subscription(scope))}
  end

  attr :notice, :atom, required: true

  defp payment_notice(assigns) do
    ~H"""
    <p
      id={notice_id(@notice)}
      role="status"
      class="m-0 flex max-w-[900px] items-start gap-2.5 rounded-tile border border-app-line-strong bg-app-raised px-5 py-3.5 text-[15px] leading-normal text-on-app"
    >
      <.icon
        :if={@notice == :confirming}
        name="hero-arrow-path"
        class="mt-0.5 size-5 shrink-0 text-on-app-2 motion-safe:animate-spin"
      />
      <.icon
        :if={@notice == :received}
        name="hero-check-circle"
        class="mt-0.5 size-5 shrink-0 text-accent"
      />
      <.icon
        :if={@notice == :may_be_counted}
        name="hero-information-circle"
        class="mt-0.5 size-5 shrink-0 text-on-app-2"
      />
      <span>{notice_text(@notice)}</span>
    </p>
    """
  end

  attr :id, :string, required: true
  attr :option, :map, required: true, doc: "a way to pay from `DirmoonWeb.OfferDisplay`"
  attr :research_includes, :list, required: true
  slot :action, required: true

  defp payment_option(assigns) do
    ~H"""
    <article
      id={"#{@id}-option"}
      class="flex flex-col gap-4 rounded-tile border border-app-line-strong bg-app-raised px-5 py-5 transition-colors duration-150 hover:border-on-app-muted"
    >
      <div class="flex flex-col gap-1">
        <h2 class="m-0 text-[17px] leading-snug font-bold">{@option.name}</h2>
        <p class="m-0 flex items-baseline gap-2">
          <span id={"#{@id}-price"} class="text-2xl leading-tight font-bold tracking-[-0.02em]">
            {@option.price}
          </span>
          <span class="text-sm text-on-app-2">{@option.price_note}</span>
        </p>
      </div>
      <p id={"#{@id}-details"} class="m-0 text-sm leading-normal text-on-app-2">{@option.details}</p>
      <div class="flex flex-col gap-2">
        <span class="font-mono text-[11px] uppercase tracking-[0.1em] text-on-app-muted">
          Each research includes:
        </span>
        <ul id={"#{@id}-includes"} class="m-0 flex list-none flex-col gap-1.5 p-0">
          <li
            :for={included <- @research_includes}
            class="flex items-start gap-2 text-sm leading-normal text-on-app-2"
          >
            <.icon name="hero-check-mini" class="mt-0.5 size-4 shrink-0 text-on-app-muted" />
            <span>{included}</span>
          </li>
        </ul>
      </div>
      <div class="mt-auto">{render_slot(@action)}</div>
    </article>
    """
  end

  attr :id, :string, required: true
  attr :product, :string, required: true
  attr :variant, :string, required: true
  slot :inner_block, required: true

  defp checkout_form(assigns) do
    ~H"""
    <.form for={%{}} id={@id} action={~p"/app/billing/checkout"}>
      <input type="hidden" name="product" value={@product} />
      <.button variant={@variant} size="large" type="submit" class="w-full">
        {render_slot(@inner_block)}
      </.button>
    </.form>
    """
  end

  defp assign_billing(socket, researches_left, subscription) do
    assign(socket,
      researches_left: researches_left,
      subscription: subscription,
      plan_state: plan_state(subscription)
    )
  end

  defp notice_at_mount(false, _researches_left), do: nil
  defp notice_at_mount(true, :unlimited), do: nil
  defp notice_at_mount(true, 0), do: :confirming
  defp notice_at_mount(true, _some_left), do: :may_be_counted

  defp notice_after_update(%{payment_return?: true, researches_left_at_mount: before}, now)
       when is_integer(before) and is_integer(now) and now > before, do: :received

  defp notice_after_update(%{payment_notice: notice}, _researches_left), do: notice

  defp notice_id(:confirming), do: "payment-confirming"
  defp notice_id(:received), do: "payment-received"
  defp notice_id(:may_be_counted), do: "payment-may-be-counted"

  defp notice_text(:confirming), do: "I'm confirming your payment…"
  defp notice_text(:received), do: "Payment received."

  defp notice_text(:may_be_counted),
    do: "If your payment isn't counted below yet, it will be as soon as Stripe confirms it."

  defp status_sentence(:unlimited, _notice, _running_plan?), do: "Your account doesn't need a plan."
  defp status_sentence(0, :confirming, _running_plan?), do: "You have no research left."
  defp status_sentence(0, _notice, true), do: "You have no research left this month. You can buy one more."
  defp status_sentence(0, _notice, false), do: "You have no research left. Pick how you want to pay."

  defp status_sentence(count, _notice, _running_plan?),
    do: "You have #{count} #{Format.plural(count, %{one: "research", other: "researches"})} left."

  defp running_plan?(nil), do: false
  defp running_plan?(%Subscription{} = subscription), do: Subscription.running?(subscription)

  defp plan_state(nil), do: %{sentence: "You don't have a monthly plan.", problem?: false}

  defp plan_state(%Subscription{} = subscription) do
    cond do
      not Subscription.running?(subscription) ->
        %{sentence: "Your monthly plan has ended.", problem?: false}

      Subscription.payment_failed?(subscription) ->
        %{
          sentence: "The last payment for your monthly plan didn't go through. Update your card in Manage plan.",
          problem?: true
        }

      subscription.ends_at ->
        %{sentence: "Your monthly plan ends on #{plain_date(subscription.ends_at)}.", problem?: false}

      Subscription.paid?(subscription) ->
        %{sentence: renewal_sentence(subscription.current_period_end), problem?: false}

      true ->
        %{sentence: "Your monthly plan needs your attention. Open Manage plan to see why.", problem?: true}
    end
  end

  defp renewal_sentence(nil), do: "Your monthly plan is active."
  defp renewal_sentence(period_end), do: "Your monthly plan renews on #{plain_date(period_end)}."

  defp plain_date(datetime), do: Calendar.strftime(datetime, "%-d %B %Y")
end
