defmodule DirmoonWeb.Controllers.StripeWebhook.CreateTest do
  use DirmoonWeb.ConnCase, async: true

  import Dirmoon.StripeEventFixtures
  import Ecto.Query

  alias Dirmoon.Billing.Allowance
  alias Dirmoon.Billing.StripeEvent
  alias Dirmoon.Repo
  alias DirmoonWeb.RawBodyReader

  @secret "whsec_test_dirmoon"

  test "a signed paid Single Research checkout answers 200 and gives the Account one more research", %{conn: conn} do
    account = paying_account()
    body = "checkout.session.completed" |> event(checkout_session(account, %{})) |> Jason.encode!()

    conn = signed_post(conn, body)

    assert json_response(conn, 200) == %{"received" => true}
    assert [%Allowance{source: :single_research, researches: 1, valid_until: nil}] = allowances_of(account)
  end

  test "the webhook verifies the request body exactly as Stripe sent it", %{conn: conn} do
    account = paying_account()
    body = "checkout.session.completed" |> event(checkout_session(account, %{})) |> Jason.encode!()

    conn = signed_post(conn, body)

    assert RawBodyReader.raw_body(conn) == body
  end

  test "the same signed event delivered twice answers 200 both times and adds one Allowance", %{conn: conn} do
    account = paying_account()
    body = "checkout.session.completed" |> event(checkout_session(account, %{})) |> Jason.encode!()

    assert conn |> signed_post(body) |> json_response(200)
    assert build_conn() |> signed_post(body) |> json_response(200)

    assert [%Allowance{}] = allowances_of(account)
  end

  test "a signed event is stored with its id, type and full payload", %{conn: conn} do
    event = event("customer.created", %{"id" => unique_stripe_customer_id(), "object" => "customer"})

    conn |> signed_post(Jason.encode!(event)) |> json_response(200)

    assert %StripeEvent{type: "customer.created", payload: payload} = stored_event(event)
    assert payload == event
  end

  test "the event is read from the signed body, not from the query string", %{conn: conn} do
    event = event("customer.created", %{"id" => unique_stripe_customer_id(), "object" => "customer"})
    body = Jason.encode!(event)

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("stripe-signature", stripe_signature(body, unix_from_now(0), @secret))
    |> post("/webhooks/stripe?type=checkout.session.completed&id=#{unique_stripe_event_id()}", body)
    |> json_response(200)

    assert %StripeEvent{type: "customer.created", payload: ^event} = stored_event(event)
  end

  @tag :capture_log
  test "a signed paid event that can't be read answers 422 and is stored unprocessed", %{conn: conn} do
    account = paying_account()
    event = event("checkout.session.completed", checkout_session(account, %{"customer" => nil}))

    conn = signed_post(conn, Jason.encode!(event))

    assert %{"error" => _message} = json_response(conn, 422)
    assert %StripeEvent{processed_at: nil} = stored_event(event)
    assert allowances_of(account) == []
  end

  test "a request whose signature doesn't match answers 400 and stores nothing", %{conn: conn} do
    account = paying_account()
    event = event("checkout.session.completed", checkout_session(account, %{}))
    body = Jason.encode!(event)

    conn = signed_post(conn, body, stripe_signature(body, unix_from_now(0), "whsec_someone_else"))

    assert %{"error" => _message} = json_response(conn, 400)
    assert stored_events(event) == []
    assert allowances_of(account) == []
  end

  test "a request signed more than five minutes ago answers 400 and stores nothing", %{conn: conn} do
    event = event("checkout.session.completed", checkout_session(paying_account(), %{}))
    body = Jason.encode!(event)

    conn = signed_post(conn, body, stripe_signature(body, unix_from_now(-301), @secret))

    assert %{"error" => _message} = json_response(conn, 400)
    assert stored_events(event) == []
  end

  test "a request whose Stripe-Signature header has no timestamp answers 400 and stores nothing", %{conn: conn} do
    event = event("checkout.session.completed", checkout_session(paying_account(), %{}))
    body = Jason.encode!(event)

    conn = signed_post(conn, body, "v1=" <> signature_hex(body, unix_from_now(0), @secret))

    assert %{"error" => _message} = json_response(conn, 400)
    assert stored_events(event) == []
  end

  test "a request signed more than five minutes ahead answers 400 and stores nothing", %{conn: conn} do
    event = event("checkout.session.completed", checkout_session(paying_account(), %{}))
    body = Jason.encode!(event)

    conn = signed_post(conn, body, stripe_signature(body, unix_from_now(600), @secret))

    assert %{"error" => _message} = json_response(conn, 400)
    assert stored_events(event) == []
  end

  test "a request without a Stripe-Signature header answers 400 and stores nothing", %{conn: conn} do
    event = event("checkout.session.completed", checkout_session(paying_account(), %{}))

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/webhooks/stripe", Jason.encode!(event))

    assert %{"error" => _message} = json_response(conn, 400)
    assert stored_events(event) == []
  end

  test "a signed JSON body that is not an object answers 400 and stores nothing", %{conn: conn} do
    stripe_event_id = unique_stripe_event_id()

    conn = signed_post(conn, Jason.encode!([%{"id" => stripe_event_id, "type" => "customer.created"}]))

    assert %{"error" => _message} = json_response(conn, 400)
    assert stripe_event_id |> stored_event_query() |> Repo.all() == []
  end

  test "a signed body that is not JSON answers 400", %{conn: conn} do
    stripe_event_id = unique_stripe_event_id()
    body = "id=#{stripe_event_id}&type=customer.created"

    conn =
      conn
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("stripe-signature", stripe_signature(body, unix_from_now(0), @secret))
      |> post(~p"/webhooks/stripe", body)

    assert %{"error" => _message} = json_response(conn, 400)
    assert stripe_event_id |> stored_event_query() |> Repo.all() == []
  end

  test "a body of a type the app doesn't read answers 400", %{conn: conn} do
    stripe_event_id = unique_stripe_event_id()
    body = Jason.encode!(%{"id" => stripe_event_id, "type" => "customer.created"})

    conn =
      conn
      |> put_req_header("content-type", "text/plain")
      |> put_req_header("stripe-signature", stripe_signature(body, unix_from_now(0), @secret))
      |> post(~p"/webhooks/stripe", body)

    assert %{"error" => _message} = json_response(conn, 400)
    assert stripe_event_id |> stored_event_query() |> Repo.all() == []
  end

  test "a body over 1,000,000 bytes is refused with 413", %{conn: conn} do
    body = ~s({"padding":") <> String.duplicate("a", 1_000_000) <> ~s("})

    assert_error_sent 413, fn -> signed_post(conn, body) end
  end

  defp signed_post(conn, body), do: signed_post(conn, body, stripe_signature(body, unix_from_now(0), @secret))

  defp signed_post(conn, body, signature) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("stripe-signature", signature)
    |> post(~p"/webhooks/stripe", body)
  end

  defp paying_account, do: insert(:account, unpaid_access: false, stripe_customer_id: unique_stripe_customer_id())

  defp allowances_of(account) do
    Allowance
    |> from(as: :allowance)
    |> where([allowance: allowance], allowance.account_id == ^account.id)
    |> Repo.all()
  end

  defp stored_event(%{"id" => stripe_event_id}), do: Repo.get_by!(StripeEvent, stripe_event_id: stripe_event_id)

  defp stored_events(%{"id" => stripe_event_id}), do: stripe_event_id |> stored_event_query() |> Repo.all()

  defp stored_event_query(stripe_event_id) do
    StripeEvent
    |> from(as: :stripe_event)
    |> where([stripe_event: stripe_event], stripe_event.stripe_event_id == ^stripe_event_id)
  end
end
