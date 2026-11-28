defmodule Dirmoon.Billing.WebhookSignatureTest do
  use ExUnit.Case, async: true

  import Dirmoon.StripeEventFixtures

  alias Dirmoon.Billing.WebhookSignature

  @secret "whsec_signature_test"
  @body ~s({"id":"evt_signature_test","type":"checkout.session.completed"})

  test "a body signed with the secret within five minutes is verified" do
    now = unix_from_now(0)

    assert WebhookSignature.verify(
             %{raw_body: @body, signature_header: stripe_signature(@body, now - 60, @secret)},
             @secret,
             now
           ) == :ok
  end

  test "a signature made exactly five minutes ago is still verified" do
    now = unix_from_now(0)

    assert WebhookSignature.verify(
             %{raw_body: @body, signature_header: stripe_signature(@body, now - 300, @secret)},
             @secret,
             now
           ) == :ok
  end

  test "the current time is used when none is given" do
    assert WebhookSignature.verify(
             %{raw_body: @body, signature_header: stripe_signature(@body, unix_from_now(0), @secret)},
             @secret
           ) == :ok
  end

  test "a header with several v1 signatures is verified when one of them matches" do
    now = unix_from_now(0)
    old_secret_signature = signature_hex(@body, now, "whsec_rolled_secret")
    header = "t=#{now},v1=#{old_secret_signature},v1=#{signature_hex(@body, now, @secret)}"

    assert WebhookSignature.verify(%{raw_body: @body, signature_header: header}, @secret, now) == :ok
  end

  test "the v0 entry and unsigned debug entries are ignored" do
    now = unix_from_now(0)

    header =
      "t=#{now},v0=#{signature_hex(@body, now, "whsec_sandbox")},v1=#{signature_hex(@body, now, @secret)}," <>
        "secret=whsec_****Test,destination=we_test,payload=a25aefc6"

    assert WebhookSignature.verify(%{raw_body: @body, signature_header: header}, @secret, now) == :ok
  end

  test "a signature only in the v0 entry is refused" do
    now = unix_from_now(0)
    header = "t=#{now},v0=#{signature_hex(@body, now, @secret)},v1=#{signature_hex(@body, now, "whsec_other")}"

    assert WebhookSignature.verify(%{raw_body: @body, signature_header: header}, @secret, now) ==
             {:error, :no_matching_signature}
  end

  test "a missing header is refused" do
    assert WebhookSignature.verify(%{raw_body: @body, signature_header: nil}, @secret, unix_from_now(0)) ==
             {:error, :missing_signature}
  end

  test "a blank header is refused as missing" do
    assert WebhookSignature.verify(%{raw_body: @body, signature_header: ""}, @secret, unix_from_now(0)) ==
             {:error, :missing_signature}
  end

  test "a header without a timestamp is refused as malformed" do
    header = "v1=#{signature_hex(@body, unix_from_now(0), @secret)}"

    assert WebhookSignature.verify(%{raw_body: @body, signature_header: header}, @secret, unix_from_now(0)) ==
             {:error, :malformed_signature}
  end

  test "a header with two timestamps is refused as malformed" do
    now = unix_from_now(0)
    header = "t=#{now},t=#{now - 1},v1=#{signature_hex(@body, now, @secret)}"

    assert WebhookSignature.verify(%{raw_body: @body, signature_header: header}, @secret, now) ==
             {:error, :malformed_signature}
  end

  test "a header whose timestamp is not a whole number is refused as malformed" do
    header = "t=12ab,v1=#{signature_hex(@body, "12ab", @secret)}"

    assert WebhookSignature.verify(%{raw_body: @body, signature_header: header}, @secret, unix_from_now(0)) ==
             {:error, :malformed_signature}
  end

  test "a header without a v1 signature is refused as malformed" do
    assert WebhookSignature.verify(
             %{raw_body: @body, signature_header: "t=#{unix_from_now(0)}"},
             @secret,
             unix_from_now(0)
           ) ==
             {:error, :malformed_signature}
  end

  test "a header that is not key=value entries is refused as malformed" do
    assert WebhookSignature.verify(%{raw_body: @body, signature_header: "garbage"}, @secret, unix_from_now(0)) ==
             {:error, :malformed_signature}
  end

  test "a signature made more than five minutes ago is refused as stale" do
    now = unix_from_now(0)

    assert WebhookSignature.verify(
             %{raw_body: @body, signature_header: stripe_signature(@body, now - 301, @secret)},
             @secret,
             now
           ) ==
             {:error, :stale_timestamp}
  end

  test "a signature dated up to five minutes ahead is verified, for clock skew" do
    now = unix_from_now(0)

    assert WebhookSignature.verify(
             %{raw_body: @body, signature_header: stripe_signature(@body, now + 300, @secret)},
             @secret,
             now
           ) == :ok
  end

  test "a signature dated more than five minutes ahead is refused" do
    now = unix_from_now(0)

    assert WebhookSignature.verify(
             %{raw_body: @body, signature_header: stripe_signature(@body, now + 301, @secret)},
             @secret,
             now
           ) ==
             {:error, :future_timestamp}
  end

  test "a body signed with another secret is refused" do
    now = unix_from_now(0)

    assert WebhookSignature.verify(
             %{raw_body: @body, signature_header: stripe_signature(@body, now, "whsec_other")},
             @secret,
             now
           ) ==
             {:error, :no_matching_signature}
  end

  test "a body signed without the whsec_ prefix of the secret is refused" do
    now = unix_from_now(0)
    unprefixed = String.replace_prefix(@secret, "whsec_", "")

    assert WebhookSignature.verify(
             %{raw_body: @body, signature_header: stripe_signature(@body, now, unprefixed)},
             @secret,
             now
           ) ==
             {:error, :no_matching_signature}
  end

  test "a body altered after signing is refused" do
    now = unix_from_now(0)
    header = stripe_signature(@body, now, @secret)

    assert WebhookSignature.verify(%{raw_body: @body <> " ", signature_header: header}, @secret, now) ==
             {:error, :no_matching_signature}
  end

  test "a signature with its timestamp changed is refused" do
    now = unix_from_now(0)
    header = "t=#{now - 1},v1=#{signature_hex(@body, now, @secret)}"

    assert WebhookSignature.verify(%{raw_body: @body, signature_header: header}, @secret, now) ==
             {:error, :no_matching_signature}
  end

  test "a signature in uppercase hex is verified like its lowercase form" do
    now = unix_from_now(0)
    header = "t=#{now},v1=#{@body |> signature_hex(now, @secret) |> String.upcase()}"

    assert WebhookSignature.verify(%{raw_body: @body, signature_header: header}, @secret, now) == :ok
  end

  test "a blank secret never verifies, even a body signed with an empty key" do
    now = unix_from_now(0)

    assert WebhookSignature.verify(%{raw_body: @body, signature_header: stripe_signature(@body, now, "")}, "", now) ==
             {:error, :missing_secret}
  end

  test "a missing secret never verifies" do
    now = unix_from_now(0)

    assert WebhookSignature.verify(%{raw_body: @body, signature_header: stripe_signature(@body, now, "")}, nil, now) ==
             {:error, :missing_secret}
  end
end
