defmodule Dirmoon.Billing.Stripe.HTTPTest do
  use ExUnit.Case, async: true

  alias Dirmoon.Billing.Stripe.HTTP

  @secret_key "sk_test_dirmoon"
  @api_version "2026-11-18.endive"
  @success_url "https://dirmoon.example/app/billing?paid=1&session_id={CHECKOUT_SESSION_ID}"
  @cancel_url "https://dirmoon.example/app/billing"

  test "creating a Customer posts the email and Account id with the key, the pinned version and a key per Account" do
    stub_answer(%{"id" => "cus_test_1", "object" => "customer"})

    HTTP.create_customer(%{email: "owner@dirmoon.example", account_id: 42})

    assert_received {:request, request}

    assert %{
             method: "POST",
             path: "/v1/customers",
             authorization: ["Bearer " <> @secret_key],
             stripe_version: [@api_version],
             idempotency_key: ["dirmoon-account-42-stripe-customer"],
             content_type: ["application/x-www-form-urlencoded" <> _charset]
           } = request

    assert request.form == %{"email" => "owner@dirmoon.example", "metadata[account_id]" => "42"}
  end

  test "creating a Customer returns its id and Stripe's answer" do
    answer = %{"id" => "cus_test_2", "object" => "customer", "email" => "owner@dirmoon.example"}
    stub_answer(answer)

    assert HTTP.create_customer(%{email: "owner@dirmoon.example", account_id: 7}) ==
             {:ok, %{result: %{id: "cus_test_2"}, raw: answer}}
  end

  test "a Single Research checkout posts a one-off payment of the single price for the Customer and Account" do
    stub_answer(%{"id" => "cs_test_1", "url" => "https://checkout.stripe.com/c/pay/cs_test_1"})

    HTTP.create_checkout_session(checkout_request(%{product: :single_research}))

    assert_received {:request, request}

    assert %{method: "POST", path: "/v1/checkout/sessions", idempotency_key: []} = request

    assert request.form == %{
             "mode" => "payment",
             "customer" => "cus_test_3",
             "client_reference_id" => "42",
             "line_items[0][price]" => "price_test_single",
             "line_items[0][quantity]" => "1",
             "success_url" => @success_url,
             "cancel_url" => @cancel_url,
             "automatic_tax[enabled]" => "false"
           }
  end

  test "a monthly plan checkout posts a subscription of the monthly price" do
    stub_answer(%{"id" => "cs_test_2", "url" => "https://checkout.stripe.com/c/pay/cs_test_2"})

    HTTP.create_checkout_session(checkout_request(%{product: :subscription}))

    assert_received {:request, %{form: %{"mode" => "subscription", "line_items[0][price]" => "price_test_monthly"}}}
  end

  test "with automatic tax off, a checkout leaves the Customer's address alone" do
    stub_answer(%{"id" => "cs_test_4", "url" => "https://checkout.stripe.com/c/pay/cs_test_4"})

    HTTP.create_checkout_session(checkout_request(%{product: :subscription}))

    assert_received {:request, %{form: form}}
    refute Map.has_key?(form, "customer_update[address]")
  end

  test "a checkout returns the session's address and id and Stripe's answer" do
    answer = %{
      "id" => "cs_test_5",
      "object" => "checkout.session",
      "url" => "https://checkout.stripe.com/c/pay/cs_test_5"
    }

    stub_answer(answer)

    assert HTTP.create_checkout_session(checkout_request(%{product: :single_research})) ==
             {:ok, %{result: %{id: "cs_test_5", url: "https://checkout.stripe.com/c/pay/cs_test_5"}, raw: answer}}
  end

  test "a portal session posts the Customer and the address to come back to" do
    stub_answer(%{"id" => "bps_test_1", "url" => "https://billing.stripe.com/p/session/test_1"})

    HTTP.create_portal_session(%{stripe_customer_id: "cus_test_4", return_url: @cancel_url})

    assert_received {:request, request}

    assert %{method: "POST", path: "/v1/billing_portal/sessions", stripe_version: [@api_version], idempotency_key: []} =
             request

    assert request.form == %{"customer" => "cus_test_4", "return_url" => @cancel_url}
  end

  test "a portal session returns its address and id and Stripe's answer" do
    answer = %{
      "id" => "bps_test_2",
      "object" => "billing_portal.session",
      "url" => "https://billing.stripe.com/p/session/test_2"
    }

    stub_answer(answer)

    assert HTTP.create_portal_session(%{stripe_customer_id: "cus_test_5", return_url: @cancel_url}) ==
             {:ok, %{result: %{id: "bps_test_2", url: "https://billing.stripe.com/p/session/test_2"}, raw: answer}}
  end

  test "a refusal returns the HTTP status and Stripe's error type and code" do
    stub_answer(
      %{"error" => %{"type" => "invalid_request_error", "code" => "resource_missing", "message" => "No such price"}},
      400
    )

    assert HTTP.create_checkout_session(checkout_request(%{product: :single_research})) ==
             {:error, {:stripe_refused, %{status: 400, type: "invalid_request_error", code: "resource_missing"}}}
  end

  test "a refusal whose error has no code returns the code as nil" do
    stub_answer(%{"error" => %{"type" => "api_error", "code" => nil}}, 500)

    assert HTTP.create_customer(%{email: "owner@dirmoon.example", account_id: 10}) ==
             {:error, {:stripe_refused, %{status: 500, type: "api_error", code: nil}}}
  end

  test "a refusal whose body is not Stripe's error shape returns the HTTP status alone" do
    Req.Test.stub(HTTP, &Plug.Conn.send_resp(&1, 502, "Bad Gateway"))

    assert HTTP.create_portal_session(%{stripe_customer_id: "cus_test_6", return_url: @cancel_url}) ==
             {:error, {:stripe_refused, %{status: 502, type: nil, code: nil}}}
  end

  test "a successful answer without the expected fields is a failure" do
    stub_answer(%{"id" => "cs_test_6", "object" => "checkout.session", "url" => nil})

    assert HTTP.create_checkout_session(checkout_request(%{product: :single_research})) ==
             {:error, {:stripe_failed, "answer without id or url"}}
  end

  test "a successful answer that is not JSON is a failure" do
    Req.Test.stub(HTTP, &Plug.Conn.send_resp(&1, 200, "OK"))

    assert HTTP.create_portal_session(%{stripe_customer_id: "cus_test_7", return_url: @cancel_url}) ==
             {:error, {:stripe_failed, "answer without id or url"}}
  end

  test "a Customer answer without an id is a failure" do
    stub_answer(%{"object" => "customer"})

    assert HTTP.create_customer(%{email: "owner@dirmoon.example", account_id: 8}) ==
             {:error, {:stripe_failed, "answer without id"}}
  end

  test "a request that never reaches Stripe returns the transport error" do
    Req.Test.stub(HTTP, &Req.Test.transport_error(&1, :timeout))

    assert HTTP.create_customer(%{email: "owner@dirmoon.example", account_id: 9}) ==
             {:error, {:stripe_unreachable, "timeout"}}
  end

  defp checkout_request(%{product: product}) do
    %{
      product: product,
      stripe_customer_id: "cus_test_3",
      account_id: 42,
      success_url: @success_url,
      cancel_url: @cancel_url
    }
  end

  defp stub_answer(body, status \\ 200) do
    test_pid = self()

    Req.Test.stub(HTTP, fn conn ->
      {:ok, raw_body, conn} = Plug.Conn.read_body(conn)

      send(test_pid, {
        :request,
        %{
          method: conn.method,
          path: conn.request_path,
          authorization: Plug.Conn.get_req_header(conn, "authorization"),
          stripe_version: Plug.Conn.get_req_header(conn, "stripe-version"),
          idempotency_key: Plug.Conn.get_req_header(conn, "idempotency-key"),
          content_type: Plug.Conn.get_req_header(conn, "content-type"),
          form: URI.decode_query(raw_body)
        }
      })

      conn
      |> Plug.Conn.put_status(status)
      |> Req.Test.json(body)
    end)
  end
end
