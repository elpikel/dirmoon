defmodule Dirmoon.Pages.Placeholders do
  @moduledoc """
  Placeholders: bracketed upper-case text (`[PRICE]`, `[PHONE]`,
  `[BUSINESS NAME]`) marking a value the business owner must
  supply. A Placeholder holds only upper-case letters, spaces and hyphens;
  any other bracketed text is ordinary text.

  `scrub/2` swaps phones, prices, e-mails and street addresses the LLM wrote
  for their Placeholders, keeping the values the User entered. It leaves
  existing Placeholders and ordinary numbers alone and is idempotent.
  """

  @placeholder_pattern "\\[\\p{Lu}[\\p{Lu} \\-]*\\]"
  @placeholder_regex Regex.compile!(@placeholder_pattern, "u")
  @whole_placeholder_regex Regex.compile!("\\A" <> @placeholder_pattern <> "\\z", "u")

  @field_placeholders %{
    phone: "[PHONE]",
    email: "[E-MAIL]",
    address: "[ADDRESS]",
    price: "[PRICE]"
  }

  @amount "(?<![\\d,.])(?>\\d{1,3}(?:[ \\x{00A0}.]\\d{3}){1,3}|\\d{1,9})(?:,\\d{1,2}|\\.\\d{2})?"
  @amount_regex Regex.compile!(@amount, "u")
  @amount_with_suffix "#{@amount}(?:,-)?(?:\\s?tys\\.?)?"
  @amount_range "#{@amount_with_suffix}(?:(?:\\s?[-–]\\s?|\\s+do\\s+)#{@amount_with_suffix})?"
  @currency_after "(?:(?i:zł(?:ot(?:y|ych|e))?)(?!\\p{L})|(?i:pln|eur|usd)(?![\\p{L}\\d])|€|\\$)"
  @currency_before "(?:€|\\$|(?<!\\p{L})(?i:eur|usd|pln)\\s?)"

  @separator "(?:\\s{1,2}|-)?"
  @mobile "\\d{3}#{@separator}\\d{3}#{@separator}\\d{3}"
  @landline "(?:\\(\\d{2}\\)|\\d{2})#{@separator}\\d{3}#{@separator}\\d{2}#{@separator}\\d{2}"
  @country_code_prefix "(?:(?:\\+|00)48#{@separator})?"

  @street_name "(?:\\d{1,2}\\s)?(?:[\\p{L}.\\-]+\\s){1,4}?"
  @street "(?<![\\p{L}.])(?:ul|al|pl|os)\\.\\s?#{@street_name}\\d+[a-zA-Z]?(?:\\s?/\\s?\\d+[a-zA-Z]?)?"
  @postal_city "(?<![\\d-])\\d{2}-\\d{3}\\s\\p{Lu}[\\p{Ll}\\-]+(?:\\s\\p{Lu}[\\p{Ll}\\-]+)?"

  @patterns [
    %{field: :email, regex: ~r/(?<![\w.+\-])[\w.+\-]++@[\w\-]++(?:\.[\w\-]++)+/u},
    %{
      field: :price,
      regex: Regex.compile!("#{@currency_before}#{@amount}|#{@amount_range}\\s?#{@currency_after}", "u")
    },
    %{
      field: :phone,
      regex: Regex.compile!("(?<![\\w+])#{@country_code_prefix}(?:#{@mobile}|#{@landline})(?!\\d)", "u")
    },
    %{field: :address, regex: Regex.compile!("#{@street}(?:,\\s#{@postal_city})?|#{@postal_city}", "u")}
  ]

  @polish_country_codes ["0048", "48"]
  @national_phone_digits 9

  @scrubbed_text_fields [:business_name, :title, :h1, :intro, :short_answer]
  @scrubbed_list_items [
    %{list: :sections, field: :question},
    %{list: :sections, field: :answer}
  ]

  @doc """
  Replaces invented phones, prices, e-mails and street addresses in `text`
  with their Placeholders, unless the match is one of the `allowed` values:
  a phone with the same digits (a leading `48`/`0048` aside), a price with
  the same amounts and currency, the same e-mail (any case), or an address
  that is a whole part of an allowed value.
  """
  def scrub(text, allowed) when is_binary(text) and is_list(allowed) do
    allowed_values = allowed_values(allowed)

    text
    |> split()
    |> Enum.map_join(fn
      %{placeholder: true, text: placeholder} -> placeholder
      %{placeholder: false, text: plain} -> scrub_plain(plain, allowed_values)
    end)
  end

  @doc """
  Applies `scrub/2` to every free-text field of a Brief: business name, title,
  H1, intro, short answer, and section questions and answers. The slug,
  phrases, primary phrase and the User's own phone, e-mail and address are
  left as they are. Takes a `Brief` struct or a
  Brief params map (string or atom keys) and returns the same shape.
  """
  def scrub_brief(brief, allowed) do
    scrubbed = scrub_fields(brief, @scrubbed_text_fields, allowed)

    Enum.reduce(@scrubbed_list_items, scrubbed, fn item, scrubbed_brief -> scrub_each(scrubbed_brief, item, allowed) end)
  end

  @doc """
  True when the whole `text` is one Placeholder, such as `[PRICE]`.
  """
  def placeholder?(text) when is_binary(text), do: Regex.match?(@whole_placeholder_regex, text)
  def placeholder?(_text), do: false

  @doc """
  Splits `text` into plain and Placeholder parts, in order, so `scrub/2`
  leaves every Placeholder as it is.
  """
  def split(text) when is_binary(text) do
    @placeholder_regex
    |> Regex.split(text, include_captures: true, trim: true)
    |> Enum.map(&%{text: &1, placeholder: placeholder?(&1)})
  end

  defp scrub_plain(text, allowed_values) do
    Enum.reduce(@patterns, text, fn %{field: field, regex: regex}, scrubbed ->
      Regex.replace(regex, scrubbed, &keep_or_replace(&1, field, allowed_values))
    end)
  end

  defp keep_or_replace(match, field, allowed_values) do
    if allowed?(field, match, allowed_values), do: match, else: Map.fetch!(@field_placeholders, field)
  end

  defp allowed_values(allowed) do
    texts = Enum.map(allowed, &normalise/1)

    %{
      phone: texts |> scan_field(:phone) |> MapSet.new(&phone_key/1),
      email: texts |> scan_field(:email) |> MapSet.new(&String.downcase/1),
      price: texts |> scan_field(:price) |> Enum.map(&price_key/1),
      address: texts
    }
  end

  defp scan_field(texts, field) do
    %{regex: regex} = Enum.find(@patterns, &(&1.field == field))

    Enum.flat_map(texts, fn text -> regex |> Regex.scan(text) |> List.flatten() end)
  end

  defp allowed?(:phone, match, %{phone: phones}), do: MapSet.member?(phones, phone_key(match))

  defp allowed?(:email, match, %{email: emails}), do: MapSet.member?(emails, String.downcase(match))

  defp allowed?(:price, match, %{price: prices}) do
    price = price_key(match)

    Enum.any?(prices, fn allowed_price ->
      allowed_price.currency == price.currency and allowed_price.thousands == price.thousands and
        price.amounts -- allowed_price.amounts == []
    end)
  end

  defp allowed?(:address, match, %{address: texts}) do
    whole_token = Regex.compile!("(?<![\\p{L}\\p{N}])" <> Regex.escape(normalise(match)) <> "(?![\\p{L}\\p{N}])", "u")

    Enum.any?(texts, &Regex.match?(whole_token, &1))
  end

  defp phone_key(phone) do
    digits = String.replace(phone, ~r/\D/, "")

    Enum.find_value(@polish_country_codes, digits, fn country_code ->
      national = String.replace_prefix(digits, country_code, "")

      if national != digits and String.length(national) == @national_phone_digits, do: national
    end)
  end

  defp price_key(price) do
    %{
      amounts: @amount_regex |> Regex.scan(price) |> List.flatten() |> Enum.map(&amount_key/1),
      currency: currency(price),
      thousands: String.contains?(price, "tys")
    }
  end

  defp amount_key(amount) do
    case Regex.run(~r/\A(.+)[,.](\d{1,2})\z/u, amount, capture: :all_but_first) do
      [whole, fraction] -> join_amount(whole, String.trim_trailing(fraction, "0"))
      nil -> join_amount(amount, "")
    end
  end

  defp join_amount(whole, ""), do: String.replace(whole, ~r/\D/u, "")
  defp join_amount(whole, fraction), do: join_amount(whole, "") <> "," <> fraction

  defp currency(price) do
    lowercase = String.downcase(price)

    cond do
      String.contains?(lowercase, ["€", "eur"]) -> :eur
      String.contains?(lowercase, ["$", "usd"]) -> :usd
      true -> :pln
    end
  end

  defp normalise(value) when is_binary(value) do
    value
    |> String.split()
    |> Enum.join(" ")
  end

  defp normalise(value), do: value |> to_string() |> normalise()

  defp scrub_fields(brief, fields, allowed) do
    Enum.reduce(fields, brief, fn field, scrubbed -> scrub_field(scrubbed, field, allowed) end)
  end

  defp scrub_field(map, field, allowed) do
    key = key_for(map, field)

    case map do
      %{^key => text} when is_binary(text) -> Map.put(map, key, scrub(text, allowed))
      _other -> map
    end
  end

  defp scrub_each(brief, %{list: list_field, field: field}, allowed) do
    key = key_for(brief, list_field)

    case brief do
      %{^key => items} when is_list(items) ->
        Map.put(brief, key, Enum.map(items, &scrub_field(&1, field, allowed)))

      %{^key => indexed_items} when is_map(indexed_items) and not is_struct(indexed_items) ->
        Map.put(brief, key, Map.new(indexed_items, fn {index, item} -> {index, scrub_field(item, field, allowed)} end))

      _other ->
        brief
    end
  end

  defp key_for(%_{}, field), do: field
  defp key_for(map, field) when is_map_key(map, field), do: field
  defp key_for(_map, field), do: Atom.to_string(field)
end
