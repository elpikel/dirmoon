defmodule DirmoonTest do
  use ExUnit.Case, async: false

  alias Dirmoon.SearchConsole.Client.Demo

  @adapter_keys ~w(llm_adapter data_for_seo_adapter search_console_adapter)a

  setup do
    original = Map.new(@adapter_keys, &{&1, Application.fetch_env!(:dirmoon, &1)})
    on_exit(fn -> Enum.each(original, fn {key, adapter} -> Application.put_env(:dirmoon, key, adapter) end) end)
  end

  test "no service is on demo data when no adapter is a demo adapter" do
    assert Dirmoon.demo_services() == []
    refute Dirmoon.demo_data?()
  end

  test "the services answered by demo adapters are named in pipeline order" do
    Application.put_env(:dirmoon, :search_console_adapter, Demo)
    Application.put_env(:dirmoon, :data_for_seo_adapter, Dirmoon.DataForSEO.Demo)

    assert Dirmoon.demo_services() == ["Google searches and competition (DataForSEO)", "Search Console"]
    assert Dirmoon.demo_data?()
  end

  test "with every adapter a demo adapter all three services are named" do
    Application.put_env(:dirmoon, :llm_adapter, Dirmoon.LLM.Demo)
    Application.put_env(:dirmoon, :data_for_seo_adapter, Dirmoon.DataForSEO.Demo)
    Application.put_env(:dirmoon, :search_console_adapter, Demo)

    assert Dirmoon.demo_services() == [
             "language model (OpenAI)",
             "Google searches and competition (DataForSEO)",
             "Search Console"
           ]
  end
end
