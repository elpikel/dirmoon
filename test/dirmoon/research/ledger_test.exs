defmodule Dirmoon.Research.LedgerTest do
  use Dirmoon.DataCase, async: true

  alias Dirmoon.Research
  alias Dirmoon.Research.ApiRequest
  alias Dirmoon.Research.Ledger

  test "a new request calls the API and returns its response" do
    run = insert(:run)

    assert {:ok, %{"items" => [%{"keyword" => "adwokat gdańsk"}]}} =
             Ledger.fetch(run, volume_request(), fn -> {:ok, %{"items" => [%{"keyword" => "adwokat gdańsk"}]}, 0.05} end)
  end

  test "a new request is recorded with its response and cost" do
    run = insert(:run)

    {:ok, _response} = Ledger.fetch(run, volume_request(), fn -> {:ok, %{"items" => []}, 0.05} end)

    assert [%ApiRequest{service: "data_for_seo", operation: "search_volume", response: %{"items" => []}} = api_request] =
             Repo.all_by(ApiRequest, run_id: run.id)

    assert Decimal.equal?(api_request.cost, Decimal.new("0.05"))
    assert api_request.request == %{"keywords" => ["adwokat gdańsk"], "location_code" => 2616}
  end

  test "a request whose API reports no cost is recorded at zero cost" do
    run = insert(:run)

    assert {:ok, %{"items" => []}} = Ledger.fetch(run, volume_request(), fn -> {:ok, %{"items" => []}, nil} end)

    assert [%ApiRequest{cost: cost}] = Repo.all_by(ApiRequest, run_id: run.id)
    assert Decimal.equal?(cost, Decimal.new(0))
    assert Decimal.equal?(Research.run_cost(run), Decimal.new(0))
  end

  test "a request the run already stored returns the stored response without calling the API" do
    run = insert(:run)
    {:ok, _response} = Ledger.fetch(run, volume_request(), fn -> {:ok, %{"items" => ["stored"]}, 0.05} end)

    assert {:ok, %{"items" => ["stored"]}} =
             Ledger.fetch(run, volume_request(), fn -> flunk("the API was called again") end)

    assert Decimal.equal?(Research.run_cost(run), Decimal.new("0.05"))
  end

  test "the same request with keys in another order is recognised as stored" do
    run = insert(:run)
    {:ok, _response} = Ledger.fetch(run, volume_request(), fn -> {:ok, %{"items" => []}, 0.05} end)
    reordered = %{volume_request() | request: %{"location_code" => 2616, "keywords" => ["adwokat gdańsk"]}}

    assert {:ok, _response} = Ledger.fetch(run, reordered, fn -> flunk("the API was called again") end)
  end

  test "the same request for another run calls the API" do
    {:ok, _response} = Ledger.fetch(insert(:run), volume_request(), fn -> {:ok, %{"items" => []}, 0.05} end)
    test_process = self()

    {:ok, _response} =
      Ledger.fetch(insert(:run), volume_request(), fn ->
        send(test_process, :api_called)
        {:ok, %{"items" => []}, 0.05}
      end)

    assert_received :api_called
  end

  test "a request recorded by another call while the API answered returns the recorded response once" do
    run = insert(:run)

    assert {:ok, %{"items" => ["first"]}} =
             Ledger.fetch(run, volume_request(), fn ->
               {:ok, _response} = Ledger.fetch(run, volume_request(), fn -> {:ok, %{"items" => ["first"]}, 0.05} end)
               {:ok, %{"items" => ["second"]}, 0.05}
             end)

    assert [%ApiRequest{response: %{"items" => ["first"]}}] = Repo.all_by(ApiRequest, run_id: run.id)
  end

  test "a failed request is returned and not recorded" do
    run = insert(:run)

    assert {:error, :timeout} = Ledger.fetch(run, volume_request(), fn -> {:error, :timeout} end)

    assert Repo.all_by(ApiRequest, run_id: run.id) == []
  end

  test "a fresh response is returned with the same string keys as a stored one" do
    run = insert(:run)

    assert {:ok, %{"items" => [%{"keyword" => "adwokat"}]}} =
             Ledger.fetch(run, volume_request(), fn -> {:ok, %{items: [%{keyword: "adwokat"}]}, 0} end)
  end

  test "decimals and dates in a request and its response are stored and returned as strings" do
    run = insert(:run)
    request = %{service: "llm", operation: "brief", request: %{"budget" => Decimal.new("0.10"), "day" => ~D[2026-11-24]}}

    assert {:ok, %{"cpc" => "0.66", "verdict" => "weak"}} =
             Ledger.fetch(run, request, fn -> {:ok, %{cpc: Decimal.new("0.66"), verdict: :weak}, 0} end)

    ledger_row = %{table: "api_requests", where: "run_id = $1", value: run.id}

    assert [%{"budget" => "0.10", "day" => "2026-11-24"}] = stored_json(Map.put(ledger_row, :column, "request"))
    assert [%{"cpc" => "0.66", "verdict" => "weak"}] = stored_json(Map.put(ledger_row, :column, "response"))
  end

  test "a request the run already stored is recorded, whatever its key order" do
    run = insert(:run)
    {:ok, _response} = Ledger.fetch(run, volume_request(), fn -> {:ok, %{"items" => []}, 0.05} end)
    reordered = %{volume_request() | request: %{"location_code" => 2616, "keywords" => ["adwokat gdańsk"]}}

    assert Ledger.recorded?(run, reordered)
  end

  test "a request only another run stored is not recorded for this run" do
    {:ok, _response} = Ledger.fetch(insert(:run), volume_request(), fn -> {:ok, %{"items" => []}, 0.05} end)

    refute Ledger.recorded?(insert(:run), volume_request())
  end

  test "a failed request is not recorded" do
    run = insert(:run)
    {:error, :timeout} = Ledger.fetch(run, volume_request(), fn -> {:error, :timeout} end)

    refute Ledger.recorded?(run, volume_request())
  end

  test "a cost given as a decimal, a whole number or a float is recorded as that amount" do
    decimal_run = insert(:run)
    integer_run = insert(:run)
    float_run = insert(:run)

    {:ok, _response} = Ledger.fetch(decimal_run, volume_request(), fn -> {:ok, %{}, Decimal.new("0.0075")} end)
    {:ok, _response} = Ledger.fetch(integer_run, volume_request(), fn -> {:ok, %{}, 2} end)
    {:ok, _response} = Ledger.fetch(float_run, volume_request(), fn -> {:ok, %{}, 0.125} end)

    assert Decimal.equal?(Research.run_cost(decimal_run), Decimal.new("0.0075"))
    assert Decimal.equal?(Research.run_cost(integer_run), Decimal.new(2))
    assert Decimal.equal?(Research.run_cost(float_run), Decimal.new("0.125"))
  end

  test "a request paid before the run existed is recorded with its answer and cost, and counts in the run's API Cost" do
    run = insert(:run)
    entry = draft_entry(%{"description" => "Hotel dla psów w Gdańsku."})

    assert Ledger.record(run, entry) == :ok

    assert [%ApiRequest{service: "llm", operation: "describe_site", request: request, response: response}] =
             Repo.all_by(ApiRequest, run_id: run.id)

    assert request == %{"task" => "describe_site", "prompt" => "Opisz stronę."}
    assert response == %{"description" => "Hotel dla psów w Gdańsku."}
    assert Decimal.equal?(Research.run_cost(run), Decimal.new("0.003"))
  end

  test "recording the same paid request twice keeps the first record" do
    run = insert(:run)

    :ok = Ledger.record(run, draft_entry(%{"description" => "Pierwszy opis."}))
    :ok = Ledger.record(run, draft_entry(%{"description" => "Drugi opis."}))

    assert [%ApiRequest{response: %{"description" => "Pierwszy opis."}}] = Repo.all_by(ApiRequest, run_id: run.id)
    assert Decimal.equal?(Research.run_cost(run), Decimal.new("0.003"))
  end

  test "a recorded request is replayed by a later fetch of the same request without calling the API" do
    run = insert(:run)
    entry = draft_entry(%{"description" => "Opis z nagrania."})
    :ok = Ledger.record(run, entry)

    assert {:ok, %{"description" => "Opis z nagrania."}} =
             Ledger.fetch(run, Map.take(entry, [:service, :operation, :request]), fn -> flunk("the API was called") end)
  end

  test "an entry without a request map, a response map or a cost is refused" do
    run = insert(:run)
    entry = draft_entry(%{"description" => "Opis."})

    for broken <- [%{entry | request: "prompt"}, %{entry | response: "opis"}, %{entry | cost: "0.003"}] do
      assert_raise FunctionClauseError, fn -> Ledger.record(run, broken) end
    end

    assert Repo.all_by(ApiRequest, run_id: run.id) == []
  end

  defp draft_entry(response) do
    %{
      service: "llm",
      operation: "describe_site",
      request: %{task: :describe_site, prompt: "Opisz stronę."},
      response: response,
      cost: Decimal.new("0.003")
    }
  end

  defp volume_request do
    %{
      service: "data_for_seo",
      operation: "search_volume",
      request: %{"keywords" => ["adwokat gdańsk"], "location_code" => 2616}
    }
  end
end
