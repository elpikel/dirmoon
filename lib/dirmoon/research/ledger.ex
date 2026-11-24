defmodule Dirmoon.Research.Ledger do
  @moduledoc """
  The record of a Research Run's paid API requests. Every paid call goes
  through `fetch/3`, so a run never pays twice for the same request and its
  API Cost is the sum of what it recorded.
  """

  import Ecto.Query

  alias Dirmoon.Repo
  alias Dirmoon.Research.ApiRequest
  alias Dirmoon.Research.Run

  @doc """
  Returns the response to `request` for the run.

  When the run already stored a response to the same service, operation and
  request (key order doesn't matter), returns it without calling
  `api_function`. Otherwise calls it; `{:ok, response, cost}` is stored with
  the request and returned as `{:ok, response}`, and `{:error, reason}` is
  returned without storing anything. Responses always come back with string
  keys, as stored. The request is stored as given, so pass the payload, never
  credentials.
  """
  def fetch(%Run{id: run_id}, %{service: service, operation: operation, request: request}, api_function)
      when is_function(api_function, 0) do
    request_hash = request_hash(%{service: service, operation: operation, request: request})

    case Repo.get_by(ApiRequest, run_id: run_id, request_hash: request_hash) do
      %ApiRequest{response: response} ->
        {:ok, response}

      nil ->
        call_and_record(
          %ApiRequest{
            run_id: run_id,
            service: to_string(service),
            operation: to_string(operation),
            request_hash: request_hash,
            request: as_stored(request)
          },
          api_function
        )
    end
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

  defp call_and_record(api_request, api_function) do
    with {:ok, response, cost} <- api_function.() do
      %{api_request | response: as_stored(response), cost: cost |> to_string() |> Decimal.new()}
      |> Repo.insert!(on_conflict: :nothing, conflict_target: [:run_id, :request_hash])
      |> recorded_response()
    end
  end

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
