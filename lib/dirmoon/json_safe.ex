defmodule Dirmoon.JsonSafe do
  @moduledoc """
  Turns a value bound for a jsonb column into plain JSON data, so what is
  stored never depends on which `Jason.Encoder` implementations a build
  happens to have. Maps and lists are walked; a `Decimal` becomes its
  decimal string, a `Date`, `Time`, `NaiveDateTime` or `DateTime` its ISO 8601
  string and an atom value (other than `true`, `false` and `nil`) its name.
  Map keys are kept as given. Any other struct raises an `ArgumentError`.
  """

  @calendar_types [Date, Time, NaiveDateTime, DateTime]

  def encode(%Decimal{} = decimal), do: Decimal.to_string(decimal, :normal)

  def encode(%type{} = calendar_value) when type in @calendar_types, do: type.to_iso8601(calendar_value)

  def encode(%type{}) do
    raise ArgumentError, "#{inspect(type)} has no JSON form; convert it before storing it in a jsonb column"
  end

  def encode(map) when is_map(map), do: Map.new(map, fn {key, value} -> {key, encode(value)} end)
  def encode(list) when is_list(list), do: Enum.map(list, &encode/1)
  def encode(value) when is_boolean(value) or is_nil(value), do: value
  def encode(atom) when is_atom(atom), do: Atom.to_string(atom)
  def encode(value), do: value
end
