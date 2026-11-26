defmodule DirmoonTest do
  use ExUnit.Case, async: false

  alias Dirmoon.DataForSEO.Demo

  @adapter_keys ~w(llm_adapter data_for_seo_adapter search_console_adapter)a

  setup do
    original = Map.new(@adapter_keys, &{&1, Application.fetch_env!(:dirmoon, &1)})
    on_exit(fn -> Enum.each(original, fn {key, adapter} -> Application.put_env(:dirmoon, key, adapter) end) end)
  end

  test "no service is on demo data when no adapter is a demo adapter" do
    assert Dirmoon.demo_services() == []
    refute Dirmoon.demo_data?()
  end

  test "the services answered by demo adapters are named" do
    Application.put_env(:dirmoon, :data_for_seo_adapter, Demo)

    assert Dirmoon.demo_services() == ["Google searches and competition (DataForSEO)"]
    assert Dirmoon.demo_data?()
  end

  test "with every demo adapter on and Search Console not configured only the language model and DataForSEO are named" do
    Application.put_env(:dirmoon, :llm_adapter, Dirmoon.LLM.Demo)
    Application.put_env(:dirmoon, :data_for_seo_adapter, Demo)
    Application.put_env(:dirmoon, :search_console_adapter, Dirmoon.SearchConsole.Client.NotConfigured)

    assert Dirmoon.demo_services() == [
             "language model (OpenAI)",
             "Google searches and competition (DataForSEO)"
           ]
  end
end
