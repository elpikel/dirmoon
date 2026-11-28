defmodule Dirmoon.Billing.WebhookSignature do
  @moduledoc """
  Checks that a webhook request came from Stripe (ADR-0004).

  Stripe signs each delivery in the `Stripe-Signature` header, comma-separated
  `key=value` entries: `t` is the Unix time it signed at and each `v1` is a
  hex HMAC-SHA256 of `"t.raw_body"` keyed with the endpoint's signing secret,
  the whole `whsec_…` string. A header may hold several `v1` entries (an old
  secret stays active for a while after it is rolled); any match passes. The
  `v0` entry and any other entry are not signed and are ignored.
  """

  @tolerance_seconds 300
  @signature_scheme "v1"

  @doc """
  `:ok` when the request's `signature_header` (the `Stripe-Signature` value,
  or nil) holds a `v1` signature of its `raw_body` made with
  `secret` at most five minutes before or after `now` (Unix seconds; a clock
  a little ahead of dirmoon's is tolerated by the same five minutes).
  Otherwise `{:error, reason}`:

    * `:missing_secret`: no secret, or a blank one, is configured
    * `:missing_signature`: no header, or a blank one
    * `:malformed_signature`: no whole-number `t` or no `v1` entry
    * `:no_matching_signature`: no `v1` matches the body and timestamp
    * `:stale_timestamp`: signed more than five minutes before `now`
    * `:future_timestamp`: signed more than five minutes after `now`
  """
  def verify(request, secret, now \\ System.system_time(:second))

  def verify(%{raw_body: _raw_body, signature_header: _signature_header}, secret, _now) when secret in [nil, ""],
    do: {:error, :missing_secret}

  def verify(%{signature_header: signature_header}, _secret, _now) when signature_header in [nil, ""],
    do: {:error, :missing_signature}

  def verify(%{raw_body: raw_body, signature_header: signature_header}, secret, now)
      when is_binary(secret) and is_binary(signature_header) do
    with {:ok, %{timestamp: timestamp, signed_at: signed_at, signatures: signatures}} <- parse(signature_header),
         :ok <- match_signature(signatures, expected_signature(raw_body, timestamp, secret)) do
      check_timestamp(signed_at, now)
    end
  end

  defp parse(signature_header) do
    entries =
      signature_header
      |> String.split(",")
      |> Enum.map(&String.split(&1, "=", parts: 2))

    timestamps = for [key, value] <- entries, String.trim(key) == "t", do: String.trim(value)
    signatures = for [key, value] <- entries, String.trim(key) == @signature_scheme, do: String.trim(value)

    case {timestamps, signatures} do
      {[timestamp], [_one | _more]} -> whole_number_timestamp(timestamp, signatures)
      _missing_or_repeated -> {:error, :malformed_signature}
    end
  end

  defp whole_number_timestamp(timestamp, signatures) do
    case Integer.parse(timestamp) do
      {signed_at, ""} -> {:ok, %{timestamp: timestamp, signed_at: signed_at, signatures: signatures}}
      _not_whole -> {:error, :malformed_signature}
    end
  end

  defp expected_signature(raw_body, timestamp, secret) do
    :hmac
    |> :crypto.mac(:sha256, secret, [timestamp, ".", raw_body])
    |> Base.encode16(case: :lower)
  end

  defp match_signature(signatures, expected) do
    if Enum.any?(signatures, &Plug.Crypto.secure_compare(String.downcase(&1), expected)),
      do: :ok,
      else: {:error, :no_matching_signature}
  end

  defp check_timestamp(signed_at, now) when now - signed_at > @tolerance_seconds, do: {:error, :stale_timestamp}
  defp check_timestamp(signed_at, now) when signed_at - now > @tolerance_seconds, do: {:error, :future_timestamp}
  defp check_timestamp(_signed_at, _now), do: :ok
end
