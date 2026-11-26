defmodule Dirmoon.Research.RunTest do
  use Dirmoon.DataCase, async: true

  alias Dirmoon.Research.Run

  test "a typed site address is reduced to its bare domain, as a run stores it" do
    assert Run.normalised_domain("  https://www.KKadwokat.pl/oferta?x=1 ") == {:ok, "kkadwokat.pl"}
    assert Run.normalised_domain("hotel-testowy.example") == {:ok, "hotel-testowy.example"}
  end

  test "a blank address, one naming no domain, or no text at all has no domain" do
    assert Run.normalised_domain("   ") == :error
    assert Run.normalised_domain("not a domain") == :error
    assert Run.normalised_domain("localhost") == :error
    assert Run.normalised_domain(nil) == :error
  end

  test "an address with a user name, password or port is reduced to its host alone" do
    assert Run.normalised_domain("user:pw@example.com:8080/x") == {:ok, "example.com"}
    assert Run.normalised_domain("example.com:22") == {:ok, "example.com"}
    assert Run.normalised_domain("https://owner@www.Example.com:443/oferta#cennik") == {:ok, "example.com"}
    assert Run.normalised_domain("ftp://example.com/plik") == {:ok, "example.com"}
  end

  test "a trailing dot goes, and an international domain is kept in its ASCII form" do
    assert Run.normalised_domain("Example.com.") == {:ok, "example.com"}
    assert Run.normalised_domain("https://Żółw.pl/oferta") == {:ok, "xn--w-uga1v8h.pl"}
    assert Run.normalised_domain("münchen.de") == {:ok, "xn--mnchen-3ya.de"}
    assert Run.normalised_domain("例え.jp") == {:ok, "xn--r8jz45g.jp"}
    assert Run.normalised_domain("xn--w-uga1v8h.pl") == {:ok, "xn--w-uga1v8h.pl"}
  end

  test "a run's domain is requested and compared in its ASCII form, also when it was stored in its Unicode form" do
    assert Run.ascii_domain(%Run{domain: "żółw.pl"}) == "xn--w-uga1v8h.pl"
    assert Run.ascii_domain(%Run{domain: "Www.Żółw.pl"}) == "xn--w-uga1v8h.pl"
    assert Run.ascii_domain(%Run{domain: "xn--w-uga1v8h.pl"}) == "xn--w-uga1v8h.pl"
    assert Run.ascii_domain(%Run{domain: "kkadwokat.pl"}) == "kkadwokat.pl"
  end

  test "a run without a domain has no ASCII domain" do
    assert Run.ascii_domain(%Run{domain: nil}) == nil
  end

  test "a full-width www and dots in an international domain go like their ASCII spelling" do
    assert Run.normalised_domain("ｗｗｗ．żółw．pl。") == {:ok, "xn--w-uga1v8h.pl"}
  end

  test "an international domain that can't be encoded, or is too long once encoded, has no domain" do
    assert Run.normalised_domain("-żółw.pl") == :error
    assert Run.normalised_domain("١٢٣.com") == :error
    assert Run.normalised_domain(String.duplicate("ż", 70) <> ".pl") == :error
    assert Run.normalised_domain(String.duplicate("żółw.", 30) <> "pl") == :error
  end

  test "Unicode look-alikes of a loopback address or localhost name what their ASCII spelling names" do
    assert Run.normalised_domain("１２７.０.０.１") == Run.normalised_domain("127.0.0.1")
    assert Run.normalised_domain("127。0。0。1") == Run.normalised_domain("127.0.0.1")
    assert Run.normalised_domain("ｌｏｃａｌｈｏｓｔ") == :error
  end

  test "a run stores an international domain in its ASCII form and refuses one that can't be encoded" do
    attrs = %{description: "Hotel dla psów", mode: :existing_site, country_code: "PL", language_code: "pl"}

    stored = Run.changeset(%Run{}, Map.put(attrs, :domain, "https://www.żółw.pl/"))
    refused = Run.changeset(%Run{}, Map.put(attrs, :domain, "-żółw.pl"))
    too_long = Run.changeset(%Run{}, Map.put(attrs, :domain, String.duplicate("żółw.", 30) <> "pl"))

    assert Ecto.Changeset.get_change(stored, :domain) == "xn--w-uga1v8h.pl"
    refute Keyword.has_key?(stored.errors, :domain)
    assert {"has invalid format", _validation} = refused.errors[:domain]
    assert {"has invalid format", _validation} = too_long.errors[:domain]
  end

  test "an address whose host is unclear or not a host name has no domain" do
    assert Run.normalised_domain("example.com\\@evil.com") == :error
    assert Run.normalised_domain("http://example.com\\evil.com/") == :error
    assert Run.normalised_domain("http://[::1]:8080/") == :error
    assert Run.normalised_domain("exa mple.com") == :error
    assert Run.normalised_domain("example..com") == :error
    assert Run.normalised_domain("example.com\u0000.pl") == :error
    assert Run.normalised_domain("https://") == :error
    assert Run.normalised_domain(String.duplicate("a", 250) <> ".com") == :error
  end

  test "a run stores the bare host of an address with a port and a password, and refuses one with a backslash" do
    attrs = %{description: "Hotel dla psów", mode: :existing_site, country_code: "PL", language_code: "pl"}

    stored = Run.changeset(%Run{}, Map.put(attrs, :domain, "user:pw@example.com:8080/x"))
    refused = Run.changeset(%Run{}, Map.put(attrs, :domain, "example.com\\@evil.com"))

    assert Ecto.Changeset.get_change(stored, :domain) == "example.com"
    refute Keyword.has_key?(stored.errors, :domain)
    assert {"has invalid format", _validation} = refused.errors[:domain]
  end

  test "results are ready once Step 7 is done" do
    run = build(:run, status: :awaiting_choice, steps: build_run_steps(Map.new(1..7, &{&1, :done})))

    assert Run.results_ready?(run)
  end

  test "results stay ready while a Brief is written or after Step 8 failed" do
    after_scoring = Map.new(1..7, &{&1, :done})
    writing = build(:run, status: :running, steps: after_scoring |> Map.put(8, :running) |> build_run_steps())
    failed = build(:run, status: :failed, steps: after_scoring |> Map.put(8, :failed) |> build_run_steps())

    assert Run.results_ready?(writing)
    assert Run.results_ready?(failed)
  end

  test "results aren't ready before Step 7 is done" do
    running =
      build(:run, status: :running, steps: 1..6 |> Map.new(&{&1, :done}) |> Map.put(7, :running) |> build_run_steps())

    failed = build(:run, status: :failed, steps: build_run_steps(%{1 => :done, 2 => :done, 3 => :failed}))

    refute Run.results_ready?(running)
    refute Run.results_ready?(failed)
  end

  test "a Niche can be chosen once results are ready and the run isn't stopped" do
    after_scoring = build_run_steps(Map.new(1..7, &{&1, :done}))
    awaiting = build(:run, status: :awaiting_choice, steps: after_scoring)
    stopped = build(:run, status: :stopped, steps: after_scoring)

    before_scoring =
      build(:run, status: :running, steps: 1..6 |> Map.new(&{&1, :done}) |> Map.put(7, :running) |> build_run_steps())

    assert Run.choosable?(awaiting)
    refute Run.choosable?(stopped)
    refute Run.choosable?(before_scoring)
  end
end
