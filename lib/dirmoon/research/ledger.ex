defmodule Dirmoon.Research.Ledger do
  @moduledoc """
  The record of a Research Run's paid API requests. Every paid call goes
  through `fetch/3`, so a run never pays twice for the same request and its
  API Cost is the sum of what it recorded.
  """

  import Ecto.Query

  alias Dirmoon.JsonSafe
  alias Dirmoon.Repo
  alias Dirmoon.Research.ApiRequest
  alias Dirmoon.Research.Run

  @doc """
  Returns the response to `request` for the run.

  When the run already stored a response to the same service, operation and
  request (key order doesn't matter), returns it without calling
  `api_function`. Otherwise calls it; `{:ok, response, cost}` is stored with
  the request (a `nil` cost as zero) and returned as `{:ok, response}`, and `{:error, reason}` is
  returned without storing anything. Responses always come back with string
  keys, as stored. The request is stored as given, so pass the payload, never
  credentials.
  """
  def fetch(%Run{} = run, %{service: _service, operation: _operation, request: _request} = paid_request, api_function)
      when is_function(api_function, 0) do
    %ApiRequest{run_id: run_id, request_hash: request_hash} = api_request = new_api_request(run, paid_request)

    case Repo.get_by(ApiRequest, run_id: run_id, request_hash: request_hash) do
      %ApiRequest{response: response} -> {:ok, response}
      nil -> call_and_record(api_request, api_function)
    end
  end

  @doc """
  Stores a request that was paid before the run existed (say, the LLM
  request that drafted the run's description) with its `response` and
  `cost`, hashed and cleaned as `fetch/3` stores one, so it counts in the
  run's API Cost and `fetch/3` replays it. Recording the same request again
  changes nothing. The entry is built by dirmoon, never taken from params:
  a `request` and `response` map and a cost.

  Returns `:ok`.
  """
  def record(
        %Run{} = run,
        %{service: _service, operation: _operation, request: request, response: response, cost: cost} = entry
      )
      when is_map(request) and is_map(response) and (is_struct(cost, Decimal) or is_number(cost) or is_nil(cost)) do
    run
    |> new_api_request(entry)
    |> insert_response(%{response: response, cost: cost})

    :ok
  end

  @doc """
  Whether the run already stored a response to the same service, operation
  and request (key order doesn't matter), so `fetch/3` would replay it
  without calling the API.
  """
  def recorded?(%Run{id: run_id}, %{service: _service, operation: _operation, request: _request} = paid_request) do
    request_hash = request_hash(paid_request)

    ApiRequest
    |> from(as: :api_request)
    |> where([api_request: api_request], api_request.run_id == ^run_id and api_request.request_hash == ^request_hash)
    |> Repo.exists?()
  end

  defp new_api_request(%Run{id: run_id}, %{service: service, operation: operation, request: request} = paid_request) do
    %ApiRequest{
      run_id: run_id,
      service: to_string(service),
      operation: to_string(operation),
      request_hash: request_hash(paid_request),
      request: as_stored(request)
    }
  end

  defp call_and_record(api_request, api_function) do
    with {:ok, response, cost} <- api_function.() do
      api_request
      |> insert_response(%{response: response, cost: cost})
      |> recorded_response()
    end
  end

  defp insert_response(api_request, %{response: response, cost: cost}) do
    Repo.insert!(%{api_request | response: as_stored(response), cost: recorded_cost(cost)},
      on_conflict: :nothing,
      conflict_target: [:run_id, :request_hash]
    )
  end

  defp recorded_cost(nil), do: Decimal.new(0)
  defp recorded_cost(cost), do: cost |> to_string() |> Decimal.new()

  defp recorded_response(%ApiRequest{id: nil, run_id: run_id, request_hash: request_hash}) do
    %ApiRequest{response: response} = Repo.get_by!(ApiRequest, run_id: run_id, request_hash: request_hash)
    {:ok, response}
  end

  defp recorded_response(%ApiRequest{response: response}), do: {:ok, response}

  defp request_hash(%{service: service, operation: operation, request: request}) do
    [to_string(service), to_string(operation), request |> as_stored() |> canonical()]
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp as_stored(data) do
    data
    |> JsonSafe.encode()
    |> Jason.encode!()
    |> Jason.decode!()
  end

  defp canonical(map) when is_map(map) do
    sorted_pairs =
      map
      |> Enum.sort_by(fn {key, _value} -> key end)
      |> Enum.map(fn {key, value} -> [key, canonical(value)] end)

    %{"map" => sorted_pairs}
  end

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  defp canonical(value), do: value
end
