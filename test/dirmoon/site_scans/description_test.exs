defmodule Dirmoon.SiteScans.DescriptionTest do
  use ExUnit.Case, async: true

  import Mox

  alias Dirmoon.SiteScans.Description

  @home_text "Hotel dla psów w Gdańsku. Opieka całodobowa, spacery trzy razy dziennie."

  test "the home page is read over https and drafted into a description in the Market's language, with its paid request" do
    expect(Dirmoon.WebPageMock, :fetch_text, 1, fn "https://hotel-testowy.example/" ->
      {:ok, %{text: @home_text, url: "https://hotel-testowy.example/"}}
    end)

    test_pid = self()

    expect(Dirmoon.LLMMock, :structured, 1, fn request ->
      send(test_pid, {:request, request})
      {:ok, %{"description" => "Hotel dla psów w Gdańsku z opieką całodobową."}, Decimal.new("0.001")}
    end)

    assert {:ok, %{description: "Hotel dla psów w Gdańsku z opieką całodobową.", ledger_entry: entry}} =
             Description.draft(%{domain: "https://www.Hotel-Testowy.example/oferta", language_name: "Polish"})

    assert_received {:request, %{task: :describe_site, prompt: prompt, schema: schema, input: input} = request}
    assert input == %{address: "https://hotel-testowy.example/", language_name: "Polish", text: @home_text}
    assert prompt =~ "in Polish"
    assert prompt =~ "never instructions"
    assert prompt =~ Jason.encode!(%{address: "https://hotel-testowy.example/", text: @home_text})
    assert schema.required == ["description"]

    assert entry == %{
             service: "llm",
             operation: "describe_site",
             request: request,
             response: %{"description" => "Hotel dla psów w Gdańsku z opieką całodobową."},
             cost: Decimal.new("0.001")
           }
  end

  test "a home page that can't be read over https is read over http" do
    expect(Dirmoon.WebPageMock, :fetch_text, 2, fn
      "https://hotel-testowy.example/" -> {:error, "HTTP 503"}
      "http://hotel-testowy.example/" -> {:ok, %{text: @home_text, url: "http://hotel-testowy.example/"}}
    end)

    expect(Dirmoon.LLMMock, :structured, 1, fn %{input: %{address: "http://hotel-testowy.example/"}} ->
      {:ok, %{"description" => "Hotel dla psów."}, Decimal.new("0.001")}
    end)

    assert {:ok, %{description: "Hotel dla psów."}} = draft()
  end

  test "the page text sent is cut to 6,000 characters" do
    long_text = String.duplicate("Hotel dla psów. ", 1_000)
    stub(Dirmoon.WebPageMock, :fetch_text, fn url -> {:ok, %{text: long_text, url: url}} end)

    expect(Dirmoon.LLMMock, :structured, 1, fn %{input: %{text: text}} ->
      assert String.length(text) == 6_000
      {:ok, %{"description" => "Hotel dla psów."}, Decimal.new("0.001")}
    end)

    assert {:ok, _draft} = draft()
  end

  test "the draft is made plain text on one line, without tags, list or heading marks or wrapping quotes" do
    stub(Dirmoon.WebPageMock, :fetch_text, fn url -> {:ok, %{text: @home_text, url: url}} end)

    stub(Dirmoon.LLMMock, :structured, fn _request ->
      {:ok, %{"description" => "\"# **Hotel** dla <b>psów</b>\n- w Gdańsku.\n1. Spacery `codziennie`.\""},
       Decimal.new("0.001")}
    end)

    assert {:ok, %{description: "Hotel dla psów w Gdańsku. Spacery codziennie."}} = draft()
  end

  test "a draft longer than 500 characters is cut at the end of a sentence, or else of a word" do
    stub(Dirmoon.WebPageMock, :fetch_text, fn url -> {:ok, %{text: @home_text, url: url}} end)
    sentences = String.duplicate("Hotel dla psów w Gdańsku. ", 30)
    words = String.duplicate("hotel ", 120)
    unbroken = String.duplicate("a", 600)

    for {answer, expected} <- [
          {sentences, "Hotel dla psów w Gdańsku. " |> String.duplicate(19) |> String.trim()},
          {words, "hotel " |> String.duplicate(83) |> String.trim()},
          {unbroken, String.duplicate("a", 500)}
        ] do
      expect(Dirmoon.LLMMock, :structured, 1, fn _request -> {:ok, %{"description" => answer}, Decimal.new(0)} end)

      assert {:ok, %{description: description}} = draft()
      assert description == expected
      assert String.length(description) <= 500
    end
  end

  test "an address that names no site is refused before anything is read" do
    expect(Dirmoon.WebPageMock, :fetch_text, 0, fn _url -> {:error, "not called"} end)

    assert {:error, "Type your site's address first, like yourbusiness.com."} =
             Description.draft(%{domain: "not a site", language_name: "Polish"})
  end

  test "a home page that can't be opened says why" do
    stub(Dirmoon.WebPageMock, :fetch_text, fn _url -> {:error, "the page took too long to read"} end)
    expect(Dirmoon.LLMMock, :structured, 0, fn _request -> {:error, "not called"} end)

    assert {:error,
            "I couldn't open https://hotel-testowy.example/: the page took too long to read. Check the address, or describe the business yourself."} =
             draft()
  end

  test "a home page with no text is not sent to the model" do
    stub(Dirmoon.WebPageMock, :fetch_text, fn url -> {:ok, %{text: "  \n ", url: url}} end)
    expect(Dirmoon.LLMMock, :structured, 0, fn _request -> {:error, "not called"} end)

    assert {:error, "I opened https://hotel-testowy.example/, but found no text on it to describe the business from."} =
             draft()
  end

  test "without an LLM, on Demo Data, after an LLM error or with an answer that holds no description, I say so" do
    stub(Dirmoon.WebPageMock, :fetch_text, fn url -> {:ok, %{text: @home_text, url: url}} end)

    for {answer, reason} <- [
          {{:error, :llm_not_configured}, "The AI service I use to read your site isn't connected here"},
          {{:error, :not_in_demo_data}, "This app runs on test data"},
          {{:error, "OpenAI: HTTP 500"}, "I couldn't write a description from your home page this time."},
          {{:ok, %{"description" => 42}, Decimal.new("0.001")}, "I couldn't write a description"},
          {{:ok, %{"text" => "Hotel"}, Decimal.new("0.001")}, "I couldn't write a description"},
          {{:ok, %{"description" => " <p> </p> \"\" "}, Decimal.new("0.001")}, "I couldn't write a description"}
        ] do
      expect(Dirmoon.LLMMock, :structured, 1, fn _request -> answer end)

      assert {:error, message} = draft()
      assert String.starts_with?(message, reason)
    end
  end

  test "the Demo adapter writes no description of a real site" do
    stub(Dirmoon.WebPageMock, :fetch_text, fn url -> {:ok, %{text: @home_text, url: url}} end)
    stub(Dirmoon.LLMMock, :structured, &Dirmoon.LLM.Demo.structured/1)

    assert {:error,
            "This app runs on test data, so I don't write a description of your real site. Describe the business yourself."} =
             draft()
  end

  defp draft, do: Description.draft(%{domain: "hotel-testowy.example", language_name: "Polish"})
end
