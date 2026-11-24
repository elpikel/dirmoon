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

  defp volume_request do
    %{
      service: "data_for_seo",
      operation: "search_volume",
      request: %{"keywords" => ["adwokat gdańsk"], "location_code" => 2616}
    }
  end
end
