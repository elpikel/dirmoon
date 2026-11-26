defmodule Dirmoon.JsonSafe do
  @moduledoc """
  Turns a value bound for a jsonb column into plain JSON data, so what is
  stored never depends on which `Jason.Encoder` implementations a build
  happens to have, nor on what bytes an outside source sent. Maps and lists
  are walked; a `Decimal` becomes its decimal string, a `Date`, `Time`,
  `NaiveDateTime` or `DateTime` its ISO 8601 string and an atom value
  (other than `true`, `false` and `nil`) its name. Every string, and every
  string map key, goes through `text/1`, since jsonb holds only UTF-8
  without NUL characters; other keys are kept as given. Any other struct
  raises an `ArgumentError`.
  """

  @calendar_types [Date, Time, NaiveDateTime, DateTime]
  @nul <<0>>

  def encode(%Decimal{} = decimal), do: Decimal.to_string(decimal, :normal)

  def encode(%type{} = calendar_value) when type in @calendar_types, do: type.to_iso8601(calendar_value)

  def encode(%type{}) do
    raise ArgumentError, "#{inspect(type)} has no JSON form; convert it before storing it in a jsonb column"
  end

  def encode(map) when is_map(map), do: Map.new(map, fn {key, value} -> {encode_key(key), encode(value)} end)
  def encode(list) when is_list(list), do: Enum.map(list, &encode/1)
  def encode(text) when is_binary(text), do: text(text)
  def encode(value) when is_boolean(value) or is_nil(value), do: value
  def encode(atom) when is_atom(atom), do: Atom.to_string(atom)
  def encode(value), do: value

  @doc "`text` as a jsonb column can hold it: bytes that are not UTF-8 replaced with U+FFFD and NUL characters dropped."
  @spec text(String.t()) :: String.t()
  def text(text) when is_binary(text), do: text |> String.replace_invalid() |> String.replace(@nul, "")

  @doc "`text/1`, then cut at a character boundary to at most `max_bytes` bytes."
  @spec text(String.t(), non_neg_integer()) :: String.t()
  def text(text, max_bytes) when is_binary(text) and is_integer(max_bytes) and max_bytes >= 0 do
    case text(text) do
      short when byte_size(short) <= max_bytes -> short
      long -> long |> binary_part(0, max_bytes) |> whole_characters()
    end
  end

  defp encode_key(key) when is_binary(key), do: text(key)
  defp encode_key(key), do: key

  defp whole_characters(prefix) do
    if String.valid?(prefix), do: prefix, else: prefix |> binary_part(0, byte_size(prefix) - 1) |> whole_characters()
  end
end
