defmodule DirmoonWeb.BillingController do
  @moduledoc """
  The plan screen's two posts (ADR-0004): `checkout/2` sends the User to
  Stripe's checkout for one product, `portal/2` to Stripe's customer portal.
  Stripe sends the User back to the plan screen, `?paid=1` after a payment.
  A problem sends the User back to the plan screen with a plain message,
  never Stripe's own error text.
  """
  use DirmoonWeb, :controller

  alias Dirmoon.Billing

  @products %{"single_research" => :single_research, "subscription" => :subscription}
  @try_again "That didn't work. Please try again."

  def checkout(conn, %{"product" => product}) when is_map_key(@products, product) do
    urls = %{success_url: url(~p"/app/billing?paid=1"), cancel_url: url(~p"/app/billing")}

    conn.assigns.current_scope
    |> Billing.checkout_url(Map.fetch!(@products, product), urls)
    |> redirect_to_stripe(conn)
  end

  def checkout(conn, _params), do: back_to_plan_screen(conn, @try_again)

  def portal(conn, _params) do
    conn.assigns.current_scope
    |> Billing.portal_url(url(~p"/app/billing"))
    |> redirect_to_stripe(conn)
  end

  defp redirect_to_stripe({:ok, stripe_url}, conn), do: redirect(conn, external: stripe_url)
  defp redirect_to_stripe({:error, reason}, conn), do: back_to_plan_screen(conn, problem(reason))

  defp problem(:not_configured), do: "Payments aren't set up yet."
  defp problem(:already_subscribed), do: "You already have the monthly plan."
  defp problem(:no_stripe_customer), do: "You haven't paid for anything yet, so there's no plan to manage."
  defp problem(_stripe_refused_failed_or_unreachable), do: @try_again

  defp back_to_plan_screen(conn, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/app/billing")
  end
end
