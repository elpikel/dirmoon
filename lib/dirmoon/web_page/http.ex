defmodule Dirmoon.WebPage.HTTP do
  @moduledoc """
  The real adapter for the web page seam, on Req: one GET per address with
  short timeouts and a generic User-Agent, redirects followed by hand so
  every address on the way passes `Dirmoon.WebPage.PublicUrl` and is
  requested at the ASCII form of its host (an international name such as
  `żółw.pl` goes out as `xn--w-uga1v8h.pl`, and the `url` answered is that
  form), and the body read up to a size cap (the rest is not downloaded) and only for readable
  content types (HTML, XHTML, plain text, XML).

  `fetch/1` follows up to five redirects, since a Site Scan reports redirect
  chains. `fetch_text/1` follows up to three, takes only a 200 HTML or
  plain-text answer, and reduces it to visible text
  (`Dirmoon.WebPage.text_page/1`) cut to a length the LLM can take.

  The receive timeout holds for each chunk; on top of it one read, its
  redirects included, has a deadline (20 s), so a server that drips its
  answer can't hold a Site Scan. The read runs in its own process under
  `Dirmoon.WebPage.ReadSupervisor` and keeps its own deadline: it gives up
  when a chunk of the body arrives past it or a redirect is due past it.
  The caller waits a little longer than the deadline and then kills the
  read, for a server that holds one request open; a watcher under the same
  supervisor kills the read when its caller dies. The Site Scan's crawler
  calls `fetch/1` from tasks linked to the scan's process
  (`Dirmoon.SiteScans.Crawler`), so killing the scan kills those callers
  and the watchers then kill their reads: a killed Site Scan leaves no read
  behind. A crash in the read is an error for the caller, never the
  caller's crash.

  Extra Req options come from `config :dirmoon, Dirmoon.WebPage.HTTP,
  req_options:`, which is where tests plug in `Req.Test`; `read_deadline:`
  (milliseconds) changes the deadline.
  """

  @behaviour Dirmoon.WebPage

  alias Dirmoon.WebPage
  alias Dirmoon.WebPage.PublicUrl

  @raw_max_redirects 5
  @text_max_redirects 3
  @max_body_bytes 2_000_000
  @connect_timeout 5_000
  @receive_timeout 10_000
  @read_deadline 20_000
  @caller_grace 500
  @read_supervisor Dirmoon.WebPage.ReadSupervisor
  @user_agent "Mozilla/5.0 (compatible; PageReader/1.0)"
  @accept "text/html,application/xhtml+xml,text/plain;q=0.9,application/xml;q=0.8,text/xml;q=0.8"
  @readable_content_types ["text/html", "application/xhtml+xml", "text/plain", "application/xml", "text/xml"]
  @redirect_statuses [301, 302, 303, 307, 308]
  @past_deadline :past_read_deadline
  @too_long "the page took too long to read"

  @impl WebPage
  def fetch(url) when is_binary(url), do: read(url, @raw_max_redirects)

  @impl WebPage
  def fetch_text(url) when is_binary(url) do
    with {:ok, page} <- read(url, @text_max_redirects) do
      WebPage.text_page(page)
    end
  end

  defp read(url, max_redirects) do
    caller = self()
    read_deadline = read_deadline()

    reading =
      Task.Supervisor.async_nolink(@read_supervisor, fn ->
        watch_caller(caller)
        deadline = System.monotonic_time(:millisecond) + read_deadline
        follow(url, %{redirects_left: max_redirects, redirects: [], deadline: deadline})
      end)

    case Task.yield(reading, read_deadline + @caller_grace) || Task.shutdown(reading, :brutal_kill) do
      {:ok, answer} -> answer
      {:exit, _reason} -> {:error, "the page could not be read"}
      nil -> {:error, @too_long}
    end
  end

  defp watch_caller(caller) do
    reader = self()

    {:ok, _watcher} =
      Task.Supervisor.start_child(@read_supervisor, fn ->
        caller_ref = Process.monitor(caller)
        reader_ref = Process.monitor(reader)

        receive do
          {:DOWN, ^caller_ref, :process, ^caller, _reason} -> Process.exit(reader, :kill)
          {:DOWN, ^reader_ref, :process, ^reader, _reason} -> :ok
        end
      end)
  end

  defp follow(url, trail) do
    with {:ok, url} <- PublicUrl.check(url),
         {:ok, response} <- get(url, trail.deadline) do
      answer(response, Map.put(trail, :url, url))
    end
  end

  defp answer(%Req.Response{status: status} = response, %{url: url} = trail) when status in @redirect_statuses do
    case {Req.Response.get_header(response, "location"), trail.redirects_left} do
      {[], _redirects_left} ->
        {:error, "redirect without an address"}

      {_location, 0} ->
        {:error, "too many redirects"}

      {[location | _rest], redirects_left} ->
        if past?(trail.deadline),
          do: {:error, @too_long},
          else:
            follow(redirect_url(url, location), %{
              trail
              | redirects_left: redirects_left - 1,
                redirects: [url | trail.redirects]
            })
    end
  end

  defp answer(%Req.Response{} = response, %{url: url, redirects: redirects}) do
    {:ok,
     %{
       url: url,
       status: response.status,
       redirects: Enum.reverse(redirects),
       content_type: content_type(response),
       body: response.body
     }}
  end

  defp get(url, deadline) do
    [
      url: url,
      method: :get,
      headers: [user_agent: @user_agent, accept: @accept],
      redirect: false,
      retry: false,
      compressed: false,
      decode_body: false,
      connect_options: [timeout: @connect_timeout],
      receive_timeout: @receive_timeout,
      into: &capped_body(&1, &2, deadline)
    ]
    |> Req.request(req_options())
    |> case do
      {:ok, %Req.Response{private: %{@past_deadline => true}}} -> {:error, @too_long}
      {:ok, response} -> {:ok, response}
      {:error, exception} -> {:error, Exception.message(exception)}
    end
  end

  defp capped_body({:data, data}, {request, response}, deadline) do
    cond do
      content_type(response) not in @readable_content_types ->
        {:halt, {request, response}}

      past?(deadline) ->
        {:halt, {request, Req.Response.put_private(response, @past_deadline, true)}}

      true ->
        body = response.body <> data

        if byte_size(body) >= @max_body_bytes,
          do: {:halt, {request, %{response | body: binary_part(body, 0, @max_body_bytes)}}},
          else: {:cont, {request, %{response | body: body}}}
    end
  end

  defp past?(deadline), do: System.monotonic_time(:millisecond) >= deadline

  defp content_type(response) do
    case Req.Response.get_header(response, "content-type") do
      [content_type | _rest] -> content_type |> String.split(";") |> hd() |> String.trim() |> String.downcase()
      [] -> nil
    end
  end

  defp redirect_url(url, location), do: url |> URI.merge(location) |> URI.to_string()

  defp req_options, do: Keyword.get(config(), :req_options, [])

  defp read_deadline, do: Keyword.get(config(), :read_deadline, @read_deadline)

  defp config, do: Application.get_env(:dirmoon, __MODULE__, [])
end
