defmodule DirmoonWeb.StripeWebhookController do
  use DirmoonWeb, :controller

  alias Dirmoon.Billing
  alias Dirmoon.Billing.WebhookSignature
  alias DirmoonWeb.RawBodyReader

  @signature_refusals [
    :missing_signature,
    :malformed_signature,
    :no_matching_signature,
    :stale_timestamp,
    :future_timestamp
  ]

  def create(conn, _params) do
    with raw_body when is_binary(raw_body) <- RawBodyReader.raw_body(conn),
         :ok <-
           WebhookSignature.verify(%{raw_body: raw_body, signature_header: signature_header(conn)}, webhook_secret()),
         {:ok, event} <- decode_event(raw_body),
         :ok <- Billing.handle_event(event) do
      json(conn, %{received: true})
    else
      nil -> refuse(conn, :no_json_body)
      {:error, reason} -> refuse(conn, reason)
    end
  end

  defp signature_header(conn) do
    case get_req_header(conn, "stripe-signature") do
      [signature_header | _more] -> signature_header
      [] -> nil
    end
  end

  defp webhook_secret, do: :dirmoon |> Application.fetch_env!(Billing) |> Keyword.get(:webhook_secret)

  defp decode_event(raw_body) do
    case Jason.decode(raw_body) do
      {:ok, %{} = event} -> {:ok, event}
      _other -> {:error, :not_an_event}
    end
  end

  defp refuse(conn, :missing_secret), do: answer(conn, 503, "The webhook is not set up yet.")
  defp refuse(conn, :no_json_body), do: answer(conn, 400, "Expected a JSON body.")
  defp refuse(conn, :not_an_event), do: answer(conn, 400, "The body is not a JSON event object.")
  defp refuse(conn, :unreadable_event), do: answer(conn, 422, "The event was stored but could not be read.")

  defp refuse(conn, signature_refused) when signature_refused in @signature_refusals,
    do: answer(conn, 400, "The signature could not be verified.")

  defp answer(conn, status, message), do: conn |> put_status(status) |> json(%{error: message})
end
