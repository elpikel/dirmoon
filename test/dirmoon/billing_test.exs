defmodule Dirmoon.BillingTest do
  use Dirmoon.DataCase, async: true

  import Dirmoon.StripeEventFixtures
  import Mox

  alias Dirmoon.Accounts.Account
  alias Dirmoon.Accounts.Membership
  alias Dirmoon.Accounts.Scope
  alias Dirmoon.Billing
  alias Dirmoon.Billing.Allowance
  alias Dirmoon.Billing.Subscription

  @checkout_urls %{
    success_url: "https://dirmoon.example/app/billing?paid=1&session_id={CHECKOUT_SESSION_ID}",
    cancel_url: "https://dirmoon.example/app/billing"
  }
  @portal_return_url "https://dirmoon.example/app/billing"

  test "an Account with Unpaid Access has unlimited researches left" do
    account = insert(:account, unpaid_access: true)

    assert Billing.researches_left(scope_for(account)) == :unlimited
  end

  test "a paying Account without Allowances has no researches left" do
    account = insert(:account, unpaid_access: false)

    assert Billing.researches_left(scope_for(account)) == 0
  end

  test "researches left are the valid Allowances' researches minus the runs that spent them" do
    account = insert(:account, unpaid_access: false)

    month =
      insert(:allowance, account: account, source: :subscription_month, researches: 10, valid_until: days_from_now(20))

    insert(:allowance, account: account, source: :single_research, researches: 1)
    insert(:run, account: account, allowance: month)
    insert(:run, account: account, allowance: month)
    insert(:run, account: account, allowance: nil)

    assert Billing.researches_left(scope_for(account)) == 9
  end

  test "a Subscription month's unused researches no longer count once the month has ended" do
    account = insert(:account, unpaid_access: false)

    ended_month =
      insert(:allowance,
        account: account,
        source: :subscription_month,
        researches: 10,
        valid_from: days_from_now(-40),
        valid_until: days_from_now(-10)
      )

    insert(:run, account: account, allowance: ended_month)
    insert(:allowance, account: account, source: :single_research, researches: 1, valid_until: nil)

    assert Billing.researches_left(scope_for(account)) == 1
  end

  test "an Allowance stops counting once its validity has ended, even a second ago" do
    ended_account = insert(:account, unpaid_access: false)
    ending_account = insert(:account, unpaid_access: false)

    insert(:allowance,
      account: ended_account,
      source: :subscription_month,
      researches: 10,
      valid_from: days_from_now(-30),
      valid_until: seconds_from_now(-1)
    )

    insert(:allowance,
      account: ending_account,
      source: :subscription_month,
      researches: 10,
      valid_from: days_from_now(-30),
      valid_until: seconds_from_now(60)
    )

    assert Billing.researches_left(scope_for(ended_account)) == 0
    assert Billing.researches_left(scope_for(ending_account)) == 10
  end

  test "a Single Research bought long ago and not used still counts as left" do
    account = insert(:account, unpaid_access: false)

    insert(:allowance,
      account: account,
      source: :single_research,
      researches: 1,
      valid_from: days_from_now(-3650),
      valid_until: nil
    )

    assert Billing.researches_left(scope_for(account)) == 1
  end

  test "an Allowance that starts later does not count yet" do
    account = insert(:account, unpaid_access: false)

    insert(:allowance,
      account: account,
      source: :subscription_month,
      researches: 10,
      valid_from: days_from_now(2),
      valid_until: days_from_now(32)
    )

    assert Billing.researches_left(scope_for(account)) == 0
  end

  test "another Account's Allowances do not count" do
    account = insert(:account, unpaid_access: false)
    insert(:allowance, account: insert(:account, unpaid_access: false), researches: 1)

    assert Billing.researches_left(scope_for(account)) == 0
  end

  test "adding an Allowance stores it on the Account" do
    account = insert(:account, unpaid_access: false)
    valid_from = days_from_now(0)
    valid_until = days_from_now(30)
    reference = unique_stripe_reference()

    assert {:ok, %Allowance{} = allowance} =
             Billing.add_allowance(account, %{
               source: :subscription_month,
               researches: 10,
               valid_from: valid_from,
               valid_until: valid_until,
               stripe_reference: reference
             })

    assert %Allowance{account_id: account_id, source: :subscription_month, researches: 10} =
             Repo.get!(Allowance, allowance.id)

    assert account_id == account.id
    assert Billing.researches_left(scope_for(account)) == 10
  end

  test "adding an Allowance by the Account's id stores it on that Account" do
    account = insert(:account, unpaid_access: false)

    assert {:ok, %Allowance{}} = Billing.add_allowance(account.id, single_research_attributes())

    assert Billing.researches_left(scope_for(account)) == 1
  end

  test "adding the same Stripe payment twice adds one Allowance" do
    account = insert(:account, unpaid_access: false)
    attributes = single_research_attributes()

    assert {:ok, %Allowance{}} = Billing.add_allowance(account, attributes)
    assert {:ok, :already_added} = Billing.add_allowance(account, attributes)

    assert Repo.aggregate(Allowance, :count) == 1
    assert Billing.researches_left(scope_for(account)) == 1
  end

  test "an Allowance with no researches or a missing field is refused" do
    account = insert(:account, unpaid_access: false)

    assert {:error, changeset} = Billing.add_allowance(account, %{single_research_attributes() | researches: 0})
    assert %{researches: ["must be greater than 0"]} = errors_on(changeset)

    assert {:error, changeset} = Billing.add_allowance(account, %{source: :single_research})

    assert %{researches: ["can't be blank"], valid_from: ["can't be blank"], stripe_reference: ["can't be blank"]} =
             errors_on(changeset)

    assert Repo.aggregate(Allowance, :count) == 0
  end

  test "the offer gives the configured prices, the month's researches and the Research Caps" do
    assert Billing.offer() == %{
             single_price: "10",
             monthly_price: "49",
             monthly_researches: 10,
             briefs_per_research: 3,
             price_checks_per_research: 3
           }
  end

  test "the owner's switch marks and unmarks a User's Account Unpaid Access" do
    user = insert(:user, memberships: [%Membership{account: build(:account, unpaid_access: false)}])

    assert {:ok, %Account{unpaid_access: true}} = Billing.set_unpaid_access(user.email, true)
    assert Repo.get!(Account, account_id_of(user)).unpaid_access

    assert {:ok, %Account{unpaid_access: false}} = Billing.set_unpaid_access(String.upcase(user.email), false)
    refute Repo.get!(Account, account_id_of(user)).unpaid_access
  end

  test "the owner's switch answers not found for an email without a User" do
    assert Billing.set_unpaid_access(unique_user_email(), true) == {:error, :not_found}
  end

  test "the owner's switch answers not found for a User without an Account" do
    user = insert(:user, memberships: [])

    assert Billing.set_unpaid_access(user.email, true) == {:error, :not_found}
  end

  test "spending a research from an Account with one Single Research picks that Allowance" do
    account = insert(:account, unpaid_access: false)
    single = insert(:allowance, account: account, source: :single_research, researches: 1)

    assert {:ok, %Allowance{id: allowance_id}} = spend_in_transaction(scope_for(account))
    assert allowance_id == single.id
  end

  test "spending a research picks the Subscription month before an unused Single Research" do
    account = insert(:account, unpaid_access: false)
    insert(:allowance, account: account, source: :single_research, researches: 1, valid_from: days_from_now(-60))

    month =
      insert(:allowance, account: account, source: :subscription_month, researches: 10, valid_until: days_from_now(20))

    assert {:ok, %Allowance{id: allowance_id}} = spend_in_transaction(scope_for(account))
    assert allowance_id == month.id
  end

  test "spending a research picks the oldest Single Research when the month has none left" do
    account = insert(:account, unpaid_access: false)

    month =
      insert(:allowance, account: account, source: :subscription_month, researches: 1, valid_until: days_from_now(20))

    insert(:run, account: account, allowance: month)
    insert(:allowance, account: account, source: :single_research, valid_from: days_from_now(-2))
    oldest = insert(:allowance, account: account, source: :single_research, valid_from: days_from_now(-9))

    assert {:ok, %Allowance{id: allowance_id}} = spend_in_transaction(scope_for(account))
    assert allowance_id == oldest.id
  end

  test "spending a research skips an ended month and an Allowance that starts later" do
    account = insert(:account, unpaid_access: false)

    insert(:allowance,
      account: account,
      source: :subscription_month,
      researches: 10,
      valid_from: days_from_now(-40),
      valid_until: days_from_now(-10)
    )

    insert(:allowance,
      account: account,
      source: :subscription_month,
      researches: 10,
      valid_from: days_from_now(2),
      valid_until: days_from_now(32)
    )

    single = insert(:allowance, account: account, source: :single_research, researches: 1)

    assert {:ok, %Allowance{id: allowance_id}} = spend_in_transaction(scope_for(account))
    assert allowance_id == single.id
  end

  test "spending a research from an Account with nothing left says no research is left" do
    account = insert(:account, unpaid_access: false)
    used = insert(:allowance, account: account, source: :single_research, researches: 1)
    insert(:run, account: account, allowance: used)
    insert(:allowance, account: insert(:account, unpaid_access: false), researches: 1)

    assert spend_in_transaction(scope_for(account)) == {:error, :no_researches_left}
  end

  test "spending a research for an Account with Unpaid Access spends no Allowance" do
    account = insert(:account, unpaid_access: true)
    insert(:allowance, account: account, researches: 1)

    assert spend_in_transaction(scope_for(account)) == {:ok, nil}
  end

  test "spending a research reads Unpaid Access from the Account as stored, not from the Scope" do
    marked = insert(:account, unpaid_access: true)
    unmarked = insert(:account, unpaid_access: false)

    assert spend_in_transaction(scope_for(%{marked | unpaid_access: false})) == {:ok, nil}

    assert spend_in_transaction(scope_for(%{unmarked | unpaid_access: true})) ==
             {:error, :no_researches_left}
  end

  test "spending a research locks the Account's row before it reads the Allowances" do
    account = insert(:account, unpaid_access: false)
    insert(:allowance, account: account, researches: 1)
    test_process = self()
    handler_id = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler_id,
        [:dirmoon, :repo, :query],
        fn _event, _measurements, %{query: query}, _config ->
          if self() == test_process, do: send(test_process, {:query, query})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    {:ok, %Allowance{}} = spend_in_transaction(scope_for(account))

    assert [account_query, allowance_query] = Enum.filter(received_queries(), &(&1 =~ "SELECT"))
    assert account_query =~ ~s(FROM "accounts")
    assert account_query =~ "FOR UPDATE"
    assert allowance_query =~ ~s(FROM "allowances")
  end

  test "once a research is spent on a run, the Account's last research can't be spent again" do
    account = insert(:account, unpaid_access: false)
    insert(:allowance, account: account, researches: 1)
    scope = scope_for(account)

    {:ok, %Allowance{} = allowance} = spend_in_transaction(scope)
    insert(:run, account: account, allowance: allowance)

    assert spend_in_transaction(scope) == {:error, :no_researches_left}
  end

  test "spending a research outside a transaction raises, since its row lock would not hold" do
    account = insert(:account, unpaid_access: false)
    insert(:allowance, account: account, researches: 1)

    assert_raise ArgumentError, ~r/must run inside the transaction that inserts the run/, fn ->
      Billing.spend_research(scope_for(account))
    end
  end

  test "a run below its Brief cap may start another Brief" do
    run = insert(:run)
    insert_list(Billing.offer().briefs_per_research - 1, :page, run: run, status: :ready)

    assert Billing.brief_allowed?(run)
  end

  test "a run whose Briefs reach the cap may start no other, being written ones included" do
    run = insert(:run)
    insert_list(Billing.offer().briefs_per_research - 1, :page, run: run, status: :ready)
    insert(:page, run: run, status: :writing, brief: nil)

    refute Billing.brief_allowed?(run)
  end

  test "failed Briefs and other runs' Briefs don't count toward a run's Brief cap" do
    run = insert(:run)
    insert_list(Billing.offer().briefs_per_research - 1, :page, run: run, status: :ready)
    insert_list(2, :page, run: run, status: :failed, error: "The model returned an invalid brief", brief: nil)
    insert(:page, status: :ready)

    assert Billing.brief_allowed?(run)
  end

  test "the Brief cap applies to a run of an Account with Unpaid Access too" do
    run = insert(:run, account: insert(:account, unpaid_access: true))
    insert_list(Billing.offer().briefs_per_research, :page, run: run, status: :ready)

    refute Billing.brief_allowed?(run)
  end

  test "a run below its Price Check cap may start another Price Check" do
    run = insert(:run)
    insert_list(Billing.offer().price_checks_per_research - 1, :price_check, run: run, status: :done)
    insert(:price_check, status: :done)

    assert Billing.price_check_allowed?(run)
  end

  test "a run whose Price Checks reach the cap may start no other, failed ones included" do
    run = insert(:run, account: insert(:account, unpaid_access: true))
    insert_list(Billing.offer().price_checks_per_research - 1, :price_check, run: run, status: :done)
    insert(:price_check, run: run, status: :failed, error: "No OpenAI API key")

    refute Billing.price_check_allowed?(run)
  end

  test "buying a Single Research creates the Account's Stripe Customer and sends the User to its checkout" do
    account = insert(:account, unpaid_access: false)
    user = build(:user)
    account_id = account.id
    email = user.email
    created_id = unique_stripe_customer_id()

    expect(Dirmoon.StripeMock, :create_customer, 1, fn %{email: ^email, account_id: ^account_id} ->
      {:ok, %{result: %{id: created_id}, raw: %{"id" => created_id}}}
    end)

    expect(Dirmoon.StripeMock, :create_checkout_session, 1, fn request ->
      assert request == %{
               product: :single_research,
               stripe_customer_id: created_id,
               account_id: account_id,
               success_url: @checkout_urls.success_url,
               cancel_url: @checkout_urls.cancel_url
             }

      checkout_session("cs_test_single")
    end)

    assert Billing.checkout_url(Scope.for_user(user, account), :single_research, @checkout_urls) ==
             {:ok, "https://checkout.stripe.com/c/pay/cs_test_single"}

    assert Repo.get!(Account, account.id).stripe_customer_id == created_id
  end

  test "subscribing sends the User to the monthly plan's checkout" do
    account = insert(:account, unpaid_access: false, stripe_customer_id: unique_stripe_customer_id())
    stripe_customer_id = account.stripe_customer_id

    expect(Dirmoon.StripeMock, :create_checkout_session, 1, fn %{
                                                                 product: :subscription,
                                                                 stripe_customer_id: ^stripe_customer_id
                                                               } ->
      checkout_session("cs_test_monthly")
    end)

    assert Billing.checkout_url(scope_for(account), :subscription, @checkout_urls) ==
             {:ok, "https://checkout.stripe.com/c/pay/cs_test_monthly"}
  end

  test "an Account that has been to checkout keeps its Stripe Customer" do
    account = insert(:account, unpaid_access: false, stripe_customer_id: unique_stripe_customer_id())
    stripe_customer_id = account.stripe_customer_id

    expect(Dirmoon.StripeMock, :create_customer, 0, fn _request -> flunk("a second Customer was created") end)

    expect(Dirmoon.StripeMock, :create_checkout_session, 1, fn %{stripe_customer_id: ^stripe_customer_id} ->
      checkout_session("cs_test_again")
    end)

    assert {:ok, _url} = Billing.checkout_url(scope_for(account), :single_research, @checkout_urls)
  end

  test "a second checkout uses the Stripe Customer the first one created, even from the same signed-in screen" do
    account = insert(:account, unpaid_access: false)
    scope = scope_for(account)
    created_id = unique_stripe_customer_id()

    expect(Dirmoon.StripeMock, :create_customer, 1, fn _request ->
      {:ok, %{result: %{id: created_id}, raw: %{}}}
    end)

    expect(Dirmoon.StripeMock, :create_checkout_session, 2, fn %{stripe_customer_id: ^created_id} ->
      checkout_session("cs_test_once")
    end)

    {:ok, _first_url} = Billing.checkout_url(scope, :single_research, @checkout_urls)

    assert {:ok, _second_url} = Billing.checkout_url(scope, :subscription, @checkout_urls)
  end

  test "when another checkout stored a Stripe Customer first, that one stays and is the one checked out" do
    account = insert(:account, unpaid_access: false)
    stored_first = unique_stripe_customer_id()
    created_later = unique_stripe_customer_id()

    expect(Dirmoon.StripeMock, :create_customer, 1, fn _request ->
      account |> change(stripe_customer_id: stored_first) |> Repo.update!()
      {:ok, %{result: %{id: created_later}, raw: %{}}}
    end)

    expect(Dirmoon.StripeMock, :create_checkout_session, 1, fn %{stripe_customer_id: ^stored_first} ->
      checkout_session("cs_test_race")
    end)

    assert {:ok, _url} = Billing.checkout_url(scope_for(account), :single_research, @checkout_urls)
    assert Repo.get!(Account, account.id).stripe_customer_id == stored_first
  end

  test "a Stripe Customer is created outside any transaction, so no row stays locked while Stripe answers" do
    account = insert(:account, unpaid_access: false)
    test_process = self()

    expect(Dirmoon.StripeMock, :create_customer, 1, fn _request ->
      send(test_process, {:in_transaction, Repo.in_transaction?()})
      {:ok, %{result: %{id: unique_stripe_customer_id()}, raw: %{}}}
    end)

    expect(Dirmoon.StripeMock, :create_checkout_session, 1, fn _request ->
      checkout_session("cs_test_outside")
    end)

    {:ok, _url} = Billing.checkout_url(scope_for(account), :single_research, @checkout_urls)

    assert_received {:in_transaction, false}
  end

  test "managing the plan sends the User to Stripe's portal for the Account's Stripe Customer" do
    account = insert(:account, unpaid_access: false, stripe_customer_id: unique_stripe_customer_id())
    stripe_customer_id = account.stripe_customer_id

    expect(Dirmoon.StripeMock, :create_portal_session, 1, fn request ->
      assert request == %{stripe_customer_id: stripe_customer_id, return_url: @portal_return_url}
      {:ok, %{result: %{id: "bps_test_1", url: "https://billing.stripe.com/p/session/test_1"}, raw: %{}}}
    end)

    assert Billing.portal_url(scope_for(account), @portal_return_url) ==
             {:ok, "https://billing.stripe.com/p/session/test_1"}
  end

  test "managing the plan uses the Stripe Customer stored after the screen was opened" do
    account = insert(:account, unpaid_access: false)
    scope = scope_for(account)
    stripe_customer_id = unique_stripe_customer_id()
    account |> change(stripe_customer_id: stripe_customer_id) |> Repo.update!()

    expect(Dirmoon.StripeMock, :create_portal_session, 1, fn %{stripe_customer_id: ^stripe_customer_id} ->
      {:ok, %{result: %{id: "bps_test_2", url: "https://billing.stripe.com/p/session/test_2"}, raw: %{}}}
    end)

    assert {:ok, _url} = Billing.portal_url(scope, @portal_return_url)
  end

  test "an Account that has never been to checkout has no plan to manage" do
    account = insert(:account, unpaid_access: false)

    expect(Dirmoon.StripeMock, :create_portal_session, 0, fn _request -> flunk("Stripe was asked") end)

    assert Billing.portal_url(scope_for(account), @portal_return_url) == {:error, :no_stripe_customer}
  end

  test "without Stripe configured a checkout fails as not configured and stores nothing" do
    account = insert(:account, unpaid_access: false)

    expect(Dirmoon.StripeMock, :create_customer, 1, fn _request -> {:error, :not_configured} end)
    expect(Dirmoon.StripeMock, :create_checkout_session, 0, fn _request -> flunk("a checkout was asked for") end)

    assert Billing.checkout_url(scope_for(account), :single_research, @checkout_urls) == {:error, :not_configured}
    assert Repo.get!(Account, account.id).stripe_customer_id == nil
  end

  test "without Stripe configured managing the plan fails as not configured" do
    account = insert(:account, unpaid_access: false, stripe_customer_id: unique_stripe_customer_id())

    expect(Dirmoon.StripeMock, :create_portal_session, 1, fn _request -> {:error, :not_configured} end)

    assert Billing.portal_url(scope_for(account), @portal_return_url) == {:error, :not_configured}
  end

  test "a checkout Stripe refuses returns Stripe's refusal, keeping the Customer already created" do
    account = insert(:account, unpaid_access: false)
    refusal = {:stripe_refused, %{status: 400, type: "invalid_request_error", code: "resource_missing"}}
    created_id = unique_stripe_customer_id()

    expect(Dirmoon.StripeMock, :create_customer, 1, fn _request ->
      {:ok, %{result: %{id: created_id}, raw: %{}}}
    end)

    expect(Dirmoon.StripeMock, :create_checkout_session, 1, fn _request -> {:error, refusal} end)

    assert Billing.checkout_url(scope_for(account), :subscription, @checkout_urls) == {:error, refusal}
    assert Repo.get!(Account, account.id).stripe_customer_id == created_id
  end

  test "a Customer Stripe refuses returns the refusal and stores nothing" do
    account = insert(:account, unpaid_access: false)

    expect(Dirmoon.StripeMock, :create_customer, 1, fn _request -> {:error, {:stripe_unreachable, "timeout"}} end)

    assert Billing.checkout_url(scope_for(account), :single_research, @checkout_urls) ==
             {:error, {:stripe_unreachable, "timeout"}}

    assert Repo.get!(Account, account.id).stripe_customer_id == nil
  end

  test "a portal session Stripe refuses returns the refusal" do
    account = insert(:account, unpaid_access: false, stripe_customer_id: unique_stripe_customer_id())
    refusal = {:stripe_refused, %{status: 500, type: "api_error", code: nil}}

    expect(Dirmoon.StripeMock, :create_portal_session, 1, fn _request -> {:error, refusal} end)

    assert Billing.portal_url(scope_for(account), @portal_return_url) == {:error, refusal}
  end

  test "an Account's Subscription is the one Stripe's events stored for it" do
    subscription = insert(:subscription)
    insert(:subscription)

    assert %Subscription{id: id} = Billing.subscription(scope_for(subscription.account))
    assert id == subscription.id
  end

  test "an Account that never subscribed has no Subscription" do
    assert Billing.subscription(scope_for(insert(:account, unpaid_access: false))) == nil
  end

  test "subscribing again while the Subscription still runs is refused before asking Stripe" do
    account = insert(:account, unpaid_access: false, stripe_customer_id: unique_stripe_customer_id())
    insert(:subscription, account: account, status: "past_due")

    assert Billing.checkout_url(scope_for(account), :subscription, @checkout_urls) == {:error, :already_subscribed}
  end

  test "a subscriber can still buy a Single Research" do
    account = insert(:account, unpaid_access: false, stripe_customer_id: unique_stripe_customer_id())
    insert(:subscription, account: account, status: "active")

    expect(Dirmoon.StripeMock, :create_checkout_session, 1, fn %{product: :single_research} ->
      checkout_session("cs_test_single_for_subscriber")
    end)

    assert Billing.checkout_url(scope_for(account), :single_research, @checkout_urls) ==
             {:ok, "https://checkout.stripe.com/c/pay/cs_test_single_for_subscriber"}
  end

  test "an Account whose Subscription was canceled can subscribe again" do
    account = insert(:account, unpaid_access: false, stripe_customer_id: unique_stripe_customer_id())
    insert(:subscription, account: account, status: "canceled")

    expect(Dirmoon.StripeMock, :create_checkout_session, 1, fn %{product: :subscription} ->
      checkout_session("cs_test_monthly_again")
    end)

    assert Billing.checkout_url(scope_for(account), :subscription, @checkout_urls) ==
             {:ok, "https://checkout.stripe.com/c/pay/cs_test_monthly_again"}
  end

  test "a subscriber hears when a paid Single Research is added to their Account" do
    account = insert(:account, unpaid_access: false, stripe_customer_id: unique_stripe_customer_id())
    Billing.subscribe(scope_for(account))

    assert Billing.handle_event(event("checkout.session.completed", checkout_session(account, %{}))) == :ok

    account_id = account.id
    assert_receive {:billing_updated, ^account_id}
  end

  test "a subscriber hears when a Subscription event is written for their Account" do
    account = insert(:account, unpaid_access: false, stripe_customer_id: unique_stripe_customer_id())
    Billing.subscribe(scope_for(account))

    assert Billing.handle_event(event("customer.subscription.created", subscription_object(account, %{}))) == :ok

    account_id = account.id
    assert_receive {:billing_updated, ^account_id}
  end

  test "a repeat delivery of an event tells no one again" do
    account = insert(:account, unpaid_access: false, stripe_customer_id: unique_stripe_customer_id())
    event = event("checkout.session.completed", checkout_session(account, %{}))
    assert Billing.handle_event(event) == :ok
    Billing.subscribe(scope_for(account))

    assert Billing.handle_event(event) == :ok

    refute_received {:billing_updated, _account_id}
  end

  test "a late Subscription event that changes nothing tells no one" do
    account = insert(:account, unpaid_access: false, stripe_customer_id: unique_stripe_customer_id())
    stored = insert(:subscription, account: account, status: "canceled", stripe_updated_at: seconds_from_now(-60))
    late = subscription_object(account, %{"id" => stored.stripe_subscription_id, "status" => "active"})
    Billing.subscribe(scope_for(account))

    assert Billing.handle_event(event("customer.subscription.updated", late, unix_from_now(-3600))) == :ok

    refute_received {:billing_updated, _account_id}
    assert %Subscription{status: "canceled"} = Billing.subscription(scope_for(account))
  end

  test "an event for another Account's Customer tells this Account's subscribers nothing" do
    account = insert(:account, unpaid_access: false, stripe_customer_id: unique_stripe_customer_id())
    other = insert(:account, unpaid_access: false, stripe_customer_id: unique_stripe_customer_id())
    Billing.subscribe(scope_for(account))

    assert Billing.handle_event(event("checkout.session.completed", checkout_session(other, %{}))) == :ok

    refute_received {:billing_updated, _account_id}
  end

  test "an event that adds nothing to any Account tells no one" do
    account = insert(:account, unpaid_access: false, stripe_customer_id: unique_stripe_customer_id())
    Billing.subscribe(scope_for(account))
    not_opened_by_dirmoon = checkout_session(account, %{"client_reference_id" => nil})

    assert Billing.handle_event(event("checkout.session.completed", not_opened_by_dirmoon)) == :ok
    assert Billing.handle_event(event("customer.created", %{"id" => account.stripe_customer_id})) == :ok

    refute_received {:billing_updated, _account_id}
  end

  defp subscription_object(account, overrides) do
    Map.merge(
      %{
        "id" => unique_stripe_subscription_id(),
        "object" => "subscription",
        "customer" => account.stripe_customer_id,
        "status" => "active",
        "cancel_at_period_end" => false,
        "cancel_at" => nil,
        "items" => %{"object" => "list", "data" => []}
      },
      overrides
    )
  end

  defp spend_in_transaction(scope), do: Repo.transact(fn -> Billing.spend_research(scope) end)

  defp received_queries do
    receive do
      {:query, query} -> [query | received_queries()]
    after
      0 -> []
    end
  end

  defp scope_for(account), do: Scope.for_user(build(:user), account)

  defp account_id_of(user) do
    [membership] = Repo.preload(user, :memberships, force: true).memberships
    membership.account_id
  end

  defp single_research_attributes do
    %{
      source: :single_research,
      researches: 1,
      valid_from: days_from_now(0),
      valid_until: nil,
      stripe_reference: unique_stripe_reference()
    }
  end

  defp days_from_now(days), do: :second |> DateTime.utc_now() |> DateTime.shift(day: days)

  defp seconds_from_now(seconds), do: :second |> DateTime.utc_now() |> DateTime.shift(second: seconds)

  defp checkout_session(id),
    do: {:ok, %{result: %{id: id, url: "https://checkout.stripe.com/c/pay/" <> id}, raw: %{"id" => id}}}
end
