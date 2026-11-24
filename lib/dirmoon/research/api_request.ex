defmodule Dirmoon.Research.ApiRequest do
  @moduledoc """
  A paid API request a Research Run made: the request payload (never
  credentials), the raw response and its API Cost in USD. Unique per run by
  `request_hash`, so a run never pays twice for the same request.
  """
  use Ecto.Schema

  alias Dirmoon.Research.Run

  schema "api_requests" do
    field :service, :string
    field :operation, :string
    field :request_hash, :string
    field :request, :map
    field :response, :map
    field :cost, :decimal, default: Decimal.new(0)

    belongs_to :run, Run

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
