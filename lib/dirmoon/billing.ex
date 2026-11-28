defmodule Dirmoon.Billing do
  @moduledoc """
  Paying for dirmoon (ADR-0004): the Allowances an Account has bought, the
  researches they still hold, Unpaid Access, and the offer shown to
  visitors, read from `config :dirmoon, Dirmoon.Billing`.

  What an Account may still start is always the researches of its valid
  Allowances minus the Research Runs that spent them, never a stored counter.
  """

  import Ecto.Query, warn: false

  alias Dirmoon.Accounts
  alias Dirmoon.Accounts.Account
  alias Dirmoon.Accounts.Scope
  alias Dirmoon.Accounts.User
  alias Dirmoon.Billing.Allowance
  alias Dirmoon.Billing.Stripe
  alias Dirmoon.Billing.StripeEvent
  alias Dirmoon.Billing.Subscription
  alias Dirmoon.Pages.Page
  alias Dirmoon.PriceChecks.PriceCheck
  alias Dirmoon.Repo
  alias Dirmoon.Research.Run

  require Logger

  @products [:single_research, :subscription]
  @offer_keys [:single_price, :monthly_price, :monthly_researches, :briefs_per_research, :price_checks_per_research]

  @doc """
  The researches the Scope's Account can still start: `:unlimited` for an
  Account with Unpaid Access, otherwise the researches of its Allowances
  valid now (started, and either without an end or ending later) minus the
  Research Runs that spent them. A Subscription month's unused researches stop
  counting once the month has ended; a Single Research never does.
  """
  def researches_left(%Scope{account: %Account{unpaid_access: true}}), do: :unlimited

  def researches_left(%Scope{account: %Account{id: account_id}}) do
    account_id
    |> valid_allowances_with_runs()
    |> select([allowance: allowance, run: run], allowance.researches - count(run.id))
    |> Repo.all()
    |> Enum.sum()
  end

  @doc """
  Picks the Allowance that starting a Research Run in the Scope's Account
  spends. It must run inside the transaction that inserts the run, and
  raises `ArgumentError` outside one: it locks the Account's row
  (`FOR UPDATE`) until that transaction ends, so two runs started at once
  can't both spend the last research. The research counts as spent once the
  run pointing at the Allowance is inserted.

  Returns `{:ok, nil}` for an Account with Unpaid Access (read from the
  locked row), `{:ok, %Allowance{}}` for the valid Allowance with a research
  left, a Subscription month's before any Single Research and then the oldest
  first, or `{:error, :no_researches_left}`.
  """
  def spend_research(%Scope{account: %Account{id: account_id}}) do
    if !Repo.in_transaction?() do
      raise ArgumentError,
            "Billing.spend_research/1 must run inside the transaction that inserts the run: " <>
              "outside one the Account's row lock is released at once and two starts could spend the last research"
    end

    account_id
    |> lock_account!()
    |> allowance_to_spend()
  end

  @doc """
  Adds an Allowance to an Account (given as the Account or its id) for one
  payment Stripe confirmed. `attrs` has `:source` (`:subscription_month` or `:single_research`),
  `:researches`, `:valid_from`, `:valid_until` (nil for no end) and
  `:stripe_reference`.

  Returns `{:ok, %Allowance{}}` when added, `{:ok, :already_added}` when an
  Allowance with that `:stripe_reference` already exists (nothing changes,
  so a webhook delivered twice adds one Allowance), or
  `{:error, %Ecto.Changeset{}}` for invalid attributes.
  """
  def add_allowance(%Account{id: account_id}, attrs), do: add_allowance(account_id, attrs)

  def add_allowance(account_id, attrs) when is_integer(account_id) do
    %Allowance{account_id: account_id}
    |> Allowance.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing, conflict_target: :stripe_reference)
    |> case do
      {:ok, %Allowance{id: nil}} -> {:ok, :already_added}
      added_or_error -> added_or_error
    end
  end

  @doc """
  The offer shown to visitors and Users, from `config :dirmoon,
  Dirmoon.Billing`: the Single Research and monthly prices (USD, as text),
  the researches a Subscription month holds and the Research Caps (Briefs and
  Price Checks per research).
  """
  @spec offer() :: %{
          single_price: String.t(),
          monthly_price: String.t(),
          monthly_researches: pos_integer(),
          briefs_per_research: pos_integer(),
          price_checks_per_research: pos_integer()
        }
  def offer do
    :dirmoon
    |> Application.fetch_env!(__MODULE__)
    |> Keyword.take(@offer_keys)
    |> Map.new()
  end

  @doc """
  Whether the run may start another Brief under its Research Cap: its Pages
  that haven't failed (being written or written) are fewer than the
  configured `briefs_per_research`. A failed Brief doesn't count. Applies to
  every run, an Unpaid Access Account's too. Callers that start a Brief call
  it with the run locked, so two requests can't both pass the cap.
  """
  def brief_allowed?(%Run{id: run_id}) do
    Page
    |> from(as: :page)
    |> where([page: page], page.run_id == ^run_id and page.status != ^:failed)
    |> Repo.aggregate(:count) < offer().briefs_per_research
  end

  @doc """
  Whether the run may start another Price Check under its Research Cap: its
  Price Checks, failed ones included, are fewer than the configured
  `price_checks_per_research`. A failed check runs again as the same check,
  so retrying it never needs this. Applies to every run, an Unpaid Access
  Account's too. Callers that start a check call it with the run locked.
  """
  def price_check_allowed?(%Run{id: run_id}) do
    PriceCheck
    |> from(as: :price_check)
    |> where([price_check: price_check], price_check.run_id == ^run_id)
    |> Repo.aggregate(:count) < offer().price_checks_per_research
  end

  @doc """
  Marks (`true`) or unmarks (`false`) the Account of the User with this email
  (the Account of their first Membership) Unpaid Access. Only the owner calls
  it, from the server console:

      bin/dirmoon rpc 'IO.inspect(Dirmoon.Billing.set_unpaid_access("owner@example.com", true))'

  `rpc` prints nothing by itself, so `IO.inspect/1` shows the answer.

  Returns `{:ok, %Account{}}`, or `{:error, :not_found}` when no User has the
  email or the User has no Account.
  """
  def set_unpaid_access(email, unpaid?) when is_binary(email) and is_boolean(unpaid?) do
    with %User{} = user <- Accounts.get_user_by_email(email),
         %Account{} = account <- Accounts.account_for_user(user) do
      account
      |> Account.unpaid_access_changeset(unpaid?)
      |> Repo.update()
    else
      nil -> {:error, :not_found}
    end
  end

  @doc """
  The address of Stripe's checkout page for one `product` (`:single_research`
  or `:subscription`), for the Scope's Account. `urls` holds the
  `success_url` and `cancel_url` Stripe sends the User back to.

  The Account's Stripe Customer is created the first time, with the User's
  email and the Account id, and stored on the Account; every later checkout
  reuses it. Stripe is asked outside any transaction, so no row stays locked
  while it answers. Two checkouts at once get the same Customer back (the
  request carries an idempotency key per Account), or one of them a refusal
  to retry; whichever id is stored first stays and is the one checked out.

  Returns `{:ok, url}`, `{:error, :already_subscribed}` for a
  `:subscription` while the Account's Subscription still runs
  (`Subscription.running?/1`; nothing is sent to Stripe), or the seam's
  `{:error, reason}` (`:not_configured` without Stripe keys, see
  `Dirmoon.Billing.Stripe`). A Customer created before a refused checkout
  stays stored.
  """
  def checkout_url(%Scope{} = scope, product, %{success_url: success_url, cancel_url: cancel_url})
      when product in @products do
    with :ok <- refuse_second_subscription(scope, product),
         {:ok, stripe_customer_id} <- stored_or_created_stripe_id(scope),
         {:ok, %{result: %{url: url}}} <-
           Stripe.create_checkout_session(%{
             product: product,
             stripe_customer_id: stripe_customer_id,
             account_id: scope.account.id,
             success_url: success_url,
             cancel_url: cancel_url
           }) do
      {:ok, url}
    end
  end

  @doc """
  The address of Stripe's customer portal for the Scope's Account, where the
  User changes or cancels the plan and their card; Stripe sends them back to
  `return_url`.

  Returns `{:ok, url}`, `{:error, :no_stripe_customer}` when the Account has
  never been to checkout (nothing is sent to Stripe), or the seam's
  `{:error, reason}`.
  """
  def portal_url(%Scope{account: %Account{id: account_id}}, return_url) when is_binary(return_url) do
    case stored_stripe_id(account_id) do
      nil ->
        {:error, :no_stripe_customer}

      stripe_customer_id ->
        with {:ok, %{result: %{url: url}}} <-
               Stripe.create_portal_session(%{stripe_customer_id: stripe_customer_id, return_url: return_url}) do
          {:ok, url}
        end
    end
  end

  @doc """
  The Scope's Account's Subscription as Stripe's events last reported it,
  or nil when it never subscribed.
  """
  def subscription(%Scope{account: %Account{id: account_id}}), do: Repo.get_by(Subscription, account_id: account_id)

  @doc """
  Acts on one Stripe webhook event, already verified and JSON-decoded
  (string keys).

  The event is stored as received on its first delivery
  (`Dirmoon.Billing.StripeEvent`), and stays stored whatever follows. Then,
  in one transaction with the stored row locked, an event already processed
  is a repeat delivery and nothing else happens; otherwise dirmoon acts on
  it and marks it processed. For the Account whose `stripe_customer_id` is
  the object's `customer`:

    * a paid payment-mode Checkout Session (`checkout.session.completed`, or
      `checkout.session.async_payment_succeeded` for a delayed payment)
      adds an Allowance of 1 research with no end, valid from the event's
      time, referenced by the session id. Only a session dirmoon opened for
      that Account counts: its `client_reference_id` must be the Account id
      (`checkout_url/3` sets it). dirmoon opens payment-mode sessions only
      for the Single Research, so the mode tells the product; the amount is
      not read, the number of researches is dirmoon's
    * `invoice.paid` for a Subscription adds an Allowance of the offer's
      `monthly_researches`, valid for the period of its non-proration
      Subscription item line that ends last, referenced by the invoice id.
      Any Subscription of the Customer counts; dirmoon only opens the
      monthly plan's
    * `customer.subscription.created`, `.updated` or `.deleted` writes the
      Account's Subscription. For the stored Subscription, an event created
      no earlier than the one it was written from overwrites it (an equal
      time too: Stripe's times are in seconds, so a same-second pair keeps
      the one delivered last). Another Subscription replaces the stored one
      only once that has ended (`Subscription.ended_statuses/0`) and by the
      same time rule, so a cancelled duplicate never overwrites the one
      still running and a late, stale event of an older Subscription never
      overwrites a newer cancellation

  Every other type, and an event whose Customer belongs to no Account, is
  only stored and marked processed. The same payment never adds two
  Allowances. Once the transaction has committed a change for an Account,
  its subscribers (`subscribe/1`) are told.

  Returns `:ok` for an event processed now or before. An event that can't
  be read is logged as a warning with its id, type and the reason (field
  names and the API version, no other values):

    * without an id or type: `{:error, :unreadable_event}`, nothing stored
      (it can't be keyed)
    * a payment or Subscription event rendered with another API release than
      the one `Dirmoon.Billing.Stripe.HTTP` pins, or a payment (paid
      Checkout Session, paid Subscription invoice) without its object, id,
      Customer or period: `{:error, :unreadable_event}`, stored but not
      processed, so the webhook answers non-2xx, Stripe retries for up to
      three days and each retry, or a resend after a fix, tries again; a
      payment is never lost
    * a Subscription without its object, id, Customer or status: processed
      with no change, `:ok`, since every later change sends the
      Subscription in full and retrying a payload that never reads helps no
      one
  """
  def handle_event(%{} = event) do
    with {:ok, _stored_or_existing} <- store_event(event) do
      fn -> event |> lock_stored_event() |> process_event(event) end
      |> Repo.transact()
      |> case do
        {:ok, changed_account_id} -> broadcast_billing_updated(changed_account_id)
        {:error, :unreadable_event} -> {:error, :unreadable_event}
      end
    end
  end

  @doc """
  Subscribes the caller to the Scope's Account's billing updates:
  `{:billing_updated, account_id}` arrives once `handle_event/1` has
  committed a change for that Account (an Allowance added, or its
  Subscription written). A repeat delivery, an event that changes nothing and
  an event for another Account send nothing.
  """
  def subscribe(%Scope{account: %Account{id: account_id}}) do
    Phoenix.PubSub.subscribe(Dirmoon.PubSub, billing_updates_channel(account_id))
  end

  defp refuse_second_subscription(scope, :subscription) do
    case subscription(scope) do
      %Subscription{} = subscription ->
        if Subscription.running?(subscription), do: {:error, :already_subscribed}, else: :ok

      nil ->
        :ok
    end
  end

  defp refuse_second_subscription(_scope, :single_research), do: :ok

  defp store_event(event) do
    event
    |> StripeEvent.changeset()
    |> Repo.insert(on_conflict: :nothing, conflict_target: :stripe_event_id)
    |> case do
      {:ok, %StripeEvent{}} = stored -> stored
      {:error, %Ecto.Changeset{}} -> unreadable(event, "an event without an id or type")
    end
  end

  defp lock_stored_event(%{"id" => stripe_event_id}) do
    StripeEvent
    |> from(as: :stripe_event)
    |> where([stripe_event: stripe_event], stripe_event.stripe_event_id == ^stripe_event_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp process_event(%StripeEvent{processed_at: %DateTime{}}, _event), do: {:ok, nil}

  defp process_event(%StripeEvent{} = stored, event) do
    with {:ok, changed_account_id} <- event |> StripeEvent.read(api_release()) |> apply_change(event),
         {:ok, _processed} <-
           stored |> Ecto.Changeset.change(processed_at: DateTime.utc_now(:second)) |> Repo.update() do
      {:ok, changed_account_id}
    end
  end

  defp broadcast_billing_updated(nil), do: :ok

  defp broadcast_billing_updated(account_id) do
    Phoenix.PubSub.broadcast(Dirmoon.PubSub, billing_updates_channel(account_id), {:billing_updated, account_id})
  end

  defp billing_updates_channel(account_id), do: "billing:account:#{account_id}"

  defp api_release do
    [_date, release] =
      :dirmoon
      |> Application.fetch_env!(Stripe.HTTP)
      |> Keyword.fetch!(:api_version)
      |> String.split(".", parts: 2)

    release
  end

  defp apply_change({:ok, %{change: :none}}, _event), do: {:ok, nil}

  defp apply_change({:ok, %{stripe_customer_id: stripe_customer_id} = change}, _event) do
    case account_by_stripe_id(stripe_customer_id) do
      %Account{id: account_id} = account -> change |> apply_to_account(account) |> changed_account(account_id)
      nil -> {:ok, nil}
    end
  end

  defp apply_change({:error, %{change: :subscription, reason: reason}}, event) do
    log_unreadable(event, reason)
    {:ok, nil}
  end

  defp apply_change({:error, %{reason: reason}}, event), do: unreadable(event, reason)

  defp apply_to_account(%{change: :single_research} = change, %Account{id: account_id} = account) do
    if change.client_reference_id == to_string(account_id) do
      add_allowance(account, %{
        source: :single_research,
        researches: 1,
        valid_from: change.paid_at,
        valid_until: nil,
        stripe_reference: change.stripe_reference
      })
    else
      {:ok, :not_opened_by_dirmoon}
    end
  end

  defp apply_to_account(%{change: :subscription_month} = change, account) do
    add_allowance(account, %{
      source: :subscription_month,
      researches: offer().monthly_researches,
      valid_from: change.period_start,
      valid_until: change.period_end,
      stripe_reference: change.stripe_reference
    })
  end

  defp apply_to_account(%{change: :subscription, subscription: attrs}, %Account{id: account_id}) do
    replacement = attrs |> Map.put(:updated_at, DateTime.utc_now(:second)) |> Keyword.new()

    newer_or_replacing_an_ended_one =
      Subscription
      |> from(as: :subscription)
      |> where(
        [subscription: subscription],
        subscription.stripe_updated_at <= ^attrs.stripe_updated_at and
          (subscription.stripe_subscription_id == ^attrs.stripe_subscription_id or
             subscription.status in ^Subscription.ended_statuses())
      )
      |> update(set: ^replacement)

    %Subscription{account_id: account_id}
    |> Subscription.changeset(attrs)
    |> Repo.insert(on_conflict: newer_or_replacing_an_ended_one, conflict_target: :account_id, allow_stale: true)
  end

  defp changed_account({:ok, %Allowance{}}, account_id), do: {:ok, account_id}
  defp changed_account({:ok, %Subscription{id: nil}}, _account_id), do: {:ok, nil}
  defp changed_account({:ok, %Subscription{}}, account_id), do: {:ok, account_id}
  defp changed_account({:ok, _already_added_or_not_opened_by_dirmoon}, _account_id), do: {:ok, nil}

  defp account_by_stripe_id(stripe_customer_id), do: Repo.get_by(Account, stripe_customer_id: stripe_customer_id)

  defp unreadable(event, reason) do
    log_unreadable(event, reason)
    {:error, :unreadable_event}
  end

  defp log_unreadable(event, reason) do
    Logger.warning("Stripe event #{inspect(event["id"])} of type #{inspect(event["type"])} could not be read: #{reason}")
  end

  defp lock_account!(account_id) do
    Account
    |> from(as: :account)
    |> where([account: account], account.id == ^account_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp allowance_to_spend(%Account{unpaid_access: true}), do: {:ok, nil}

  defp allowance_to_spend(%Account{id: account_id}) do
    account_id
    |> valid_allowances_with_runs()
    |> having([allowance: allowance, run: run], allowance.researches > count(run.id))
    |> order_by([allowance: allowance],
      desc: allowance.source == ^:subscription_month,
      asc: allowance.valid_from,
      asc: allowance.id
    )
    |> limit(1)
    |> Repo.one()
    |> case do
      %Allowance{} = allowance -> {:ok, allowance}
      nil -> {:error, :no_researches_left}
    end
  end

  defp valid_allowances_with_runs(account_id) do
    now = DateTime.utc_now(:second)

    Allowance
    |> from(as: :allowance)
    |> where([allowance: allowance], allowance.account_id == ^account_id)
    |> where([allowance: allowance], allowance.valid_from <= ^now)
    |> where([allowance: allowance], is_nil(allowance.valid_until) or allowance.valid_until > ^now)
    |> join(:left, [allowance: allowance], run in assoc(allowance, :runs), as: :run)
    |> group_by([allowance: allowance], allowance.id)
  end

  defp stored_or_created_stripe_id(%Scope{account: %Account{id: account_id}, user: %User{email: email}}) do
    case stored_stripe_id(account_id) do
      nil -> create_and_store_stripe_id(account_id, email)
      stripe_customer_id -> {:ok, stripe_customer_id}
    end
  end

  defp create_and_store_stripe_id(account_id, email) do
    with {:ok, %{result: %{id: created_id}}} <- Stripe.create_customer(%{email: email, account_id: account_id}) do
      Account
      |> from(as: :account)
      |> where([account: account], account.id == ^account_id and is_nil(account.stripe_customer_id))
      |> Repo.update_all(set: [stripe_customer_id: created_id, updated_at: DateTime.utc_now(:second)])

      {:ok, stored_stripe_id(account_id)}
    end
  end

  defp stored_stripe_id(account_id) do
    Account
    |> from(as: :account)
    |> where([account: account], account.id == ^account_id)
    |> select([account: account], account.stripe_customer_id)
    |> Repo.one!()
  end
end
