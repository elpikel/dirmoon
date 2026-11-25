defmodule Dirmoon.WebPageTest do
  use ExUnit.Case, async: true

  import Mox

  alias Dirmoon.WebPage

  test "a page is read by the configured adapter" do
    expect(Dirmoon.WebPageMock, :fetch_text, 1, fn "https://lodowisko-testowe.example/" ->
      {:ok, %{text: "Cennik", url: "https://lodowisko-testowe.example/cennik"}}
    end)

    assert {:ok, %{text: "Cennik", url: "https://lodowisko-testowe.example/cennik"}} =
             WebPage.fetch_text("https://lodowisko-testowe.example/")
  end

  test "dev and production read pages with the real adapter, no credentials needed" do
    for env <- [:dev, :prod] do
      config = Config.Reader.read!("config/config.exs", env: env)

      assert get_in(config, [:dirmoon, :web_page_adapter]) == Dirmoon.WebPage.HTTP
    end
  end
end
