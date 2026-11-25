defmodule Dirmoon.WebPage.HTTP do
  @moduledoc """
  The real adapter for the web page seam, on Req: one GET with short
  timeouts and a generic User-Agent, redirects followed by hand (at most
  three) so every address on the way passes `Dirmoon.WebPage.PublicUrl`,
  only HTML or plain-text answers, the body read up to a size cap (the
  rest is not downloaded), then reduced to visible text
  (`Dirmoon.WebPage.VisibleText`) and cut to a length the LLM can take.

  Extra Req options come from `config :dirmoon, Dirmoon.WebPage.HTTP,
  req_options:`, which is where tests plug in `Req.Test`.
  """

  @behaviour Dirmoon.WebPage

  alias Dirmoon.WebPage.PublicUrl
  alias Dirmoon.WebPage.VisibleText

  @max_redirects 3
  @max_body_bytes 2_000_000
  @max_text_length 15_000
  @connect_timeout 5_000
  @receive_timeout 10_000
  @user_agent "Mozilla/5.0 (compatible; PageReader/1.0)"
  @accepted_content_types ["text/html", "application/xhtml+xml", "text/plain"]
  @redirect_statuses [301, 302, 303, 307, 308]

  @impl Dirmoon.WebPage
  def fetch_text(url) when is_binary(url), do: follow(url, @max_redirects)

  defp follow(url, redirects_left) do
    with :ok <- PublicUrl.check(url),
         {:ok, response} <- get(url) do
      answer(response, %{url: url, redirects_left: redirects_left})
    end
  end

  defp answer(%Req.Response{status: status} = response, %{url: url, redirects_left: redirects_left})
       when status in @redirect_statuses do
    case {Req.Response.get_header(response, "location"), redirects_left} do
      {[], _redirects_left} -> {:error, "redirect without an address"}
      {_location, 0} -> {:error, "too many redirects"}
      {[location | _rest], _redirects_left} -> follow(redirect_url(url, location), redirects_left - 1)
    end
  end

  defp answer(%Req.Response{status: 200} = response, %{url: url}) do
    if text_content?(response),
      do: {:ok, %{text: VisibleText.from_html(response.body, @max_text_length), url: url}},
      else: {:error, "not an HTML page"}
  end

  defp answer(%Req.Response{status: status}, _context), do: {:error, "HTTP #{status}"}

  defp get(url) do
    [
      url: url,
      method: :get,
      headers: [user_agent: @user_agent, accept: "text/html,application/xhtml+xml,text/plain;q=0.9"],
      redirect: false,
      retry: false,
      compressed: false,
      decode_body: false,
      connect_options: [timeout: @connect_timeout],
      receive_timeout: @receive_timeout,
      into: &capped_body/2
    ]
    |> Req.request(req_options())
    |> case do
      {:ok, response} -> {:ok, response}
      {:error, exception} -> {:error, Exception.message(exception)}
    end
  end

  defp capped_body({:data, data}, {request, response}) do
    if text_content?(response) do
      body = response.body <> data

      if byte_size(body) >= @max_body_bytes,
        do: {:halt, {request, %{response | body: binary_part(body, 0, @max_body_bytes)}}},
        else: {:cont, {request, %{response | body: body}}}
    else
      {:halt, {request, response}}
    end
  end

  defp text_content?(response) do
    response
    |> Req.Response.get_header("content-type")
    |> Enum.any?(fn content_type ->
      media_type = content_type |> String.split(";") |> hd() |> String.trim() |> String.downcase()
      media_type in @accepted_content_types
    end)
  end

  defp redirect_url(url, location), do: url |> URI.merge(location) |> URI.to_string()

  defp req_options do
    :dirmoon
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:req_options, [])
  end
end
