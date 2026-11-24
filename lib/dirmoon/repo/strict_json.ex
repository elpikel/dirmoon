defmodule Dirmoon.Repo.StrictJson do
  @moduledoc """
  The JSON library Postgrex uses for every jsonb value the Repo writes. It is
  Jason, except that a `Decimal` anywhere in the value raises: Jason encodes a
  `Decimal` only when it happened to be compiled with Decimal support, so a
  value with one would store in one build and crash in another. Convert such
  values with `Dirmoon.JsonSafe.encode/1` before they reach a jsonb column.
  """

  def encode_to_iodata!(value) do
    refuse_decimals!(value)
    Jason.encode_to_iodata!(value)
  end

  def decode!(json), do: Jason.decode!(json)

  defp refuse_decimals!(%Decimal{} = decimal) do
    raise ArgumentError,
          "Decimal #{decimal} in a jsonb value; convert it with Dirmoon.JsonSafe.encode/1 before storing it"
  end

  defp refuse_decimals!(%_type{}), do: :ok
  defp refuse_decimals!(map) when is_map(map), do: Enum.each(map, fn {_key, value} -> refuse_decimals!(value) end)
  defp refuse_decimals!(list) when is_list(list), do: Enum.each(list, &refuse_decimals!/1)
  defp refuse_decimals!(_value), do: :ok
end
