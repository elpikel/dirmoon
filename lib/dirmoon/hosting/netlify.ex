defmodule Dirmoon.Hosting.Netlify do
  @moduledoc """
  The Netlify adapter over HTTP (Req), per `.claude/work/dirmoon-v1/notes-netlify.md`.

  `create_site/1` creates a site (`POST /api/v1/sites`) named after the
  site name; a name Netlify reports taken (422 mentioning `subdomain`) is
  tried once more with a random suffix. `deploy/1` sends a zip holding only
  `index.html` to an existing site (`POST /api/v1/sites/:id/deploys`) and
  polls `GET /api/v1/deploys/:id` until the deploy is `ready` (the answer
  is the site's https URL) or `error`.

  Configured by `config :dirmoon, Dirmoon.Hosting.Netlify` with `token`,
  `base_url`, `req_options`, `poll_interval_ms` and `poll_attempts`. The
  token travels only in the Bearer header and is cut out of every error.
  """

  @behaviour Dirmoon.Hosting

  alias Dirmoon.Hosting

  @default_base_url "https://api.netlify.com"
  @default_poll_interval_ms 3_000
  @default_poll_attempts 100
  @receive_timeout 60_000
  @user_agent "dirmoon"
  @suffix_length 4
  @max_name_length 63 - @suffix_length - 1
  @failed_states ["error", "rejected"]
  @hidden_token "[TOKEN]"

  @impl Hosting
  def create_site(%{site_name: site_name}) do
    with_netlify(fn netlify ->
      name = Hosting.site_name(site_name, @max_name_length)

      netlify.client
      |> post_site(name)
      |> retry_taken_name(%{client: netlify.client, name: name})
      |> created_site()
    end)
  end

  @impl Hosting
  def deploy(%{site_id: site_id, html: html}) when is_binary(site_id) and site_id != "" and is_binary(html) do
    with_netlify(fn netlify ->
      with {:ok, zip} <- zip(html),
           {:ok, deploy} <- create_deploy(netlify.client, %{site_id: site_id, zip: zip}),
           {:ok, url} <- await_ready(netlify, deploy, netlify.poll_attempts) do
        {:ok, %{url: url}}
      end
    end)
  end

  defp with_netlify(call) do
    config = Application.get_env(:dirmoon, __MODULE__, [])

    case Keyword.get(config, :token) do
      token when is_binary(token) and token != "" ->
        %{
          client: client(config, token),
          poll_interval_ms: Keyword.get(config, :poll_interval_ms, @default_poll_interval_ms),
          poll_attempts: Keyword.get(config, :poll_attempts, @default_poll_attempts)
        }
        |> call.()
        |> without_token(token)

      _missing ->
        {:error, :hosting_not_configured}
    end
  end

  defp client(config, token) do
    [
      base_url: Keyword.get(config, :base_url, @default_base_url),
      auth: {:bearer, token},
      headers: [user_agent: @user_agent],
      receive_timeout: @receive_timeout,
      retry: false
    ]
    |> Req.new()
    |> Req.merge(Keyword.get(config, :req_options, []))
  end

  defp post_site(client, name), do: request(client, method: :post, url: "/api/v1/sites", json: %{name: name})

  defp retry_taken_name({:error, response} = failed, %{client: client, name: name}) do
    if name_taken?(response), do: post_site(client, name <> "-" <> random_suffix()), else: failed
  end

  defp retry_taken_name(created, _site), do: created

  defp created_site({:ok, %{"id" => site_id}}) when is_binary(site_id) and site_id != "", do: {:ok, %{site_id: site_id}}
  defp created_site({:ok, _body}), do: failure("odpowiedź bez id strony")
  defp created_site({:error, response}), do: failure(response)

  defp zip(html) do
    case :zip.create(~c"site.zip", [{~c"index.html", html}], [:memory]) do
      {:ok, {_filename, zip}} -> {:ok, zip}
      {:error, reason} -> failure("nie udało się spakować strony (#{inspect(reason)})")
    end
  end

  defp create_deploy(client, %{site_id: site_id, zip: zip}) do
    client
    |> request(
      method: :post,
      url: "/api/v1/sites/#{encode_segment(site_id)}/deploys",
      headers: [content_type: "application/zip"],
      body: zip
    )
    |> case do
      {:ok, %{"id" => deploy_id} = deploy} when is_binary(deploy_id) -> {:ok, deploy}
      {:ok, _body} -> failure("odpowiedź bez id deployu")
      {:error, response} -> failure(response)
    end
  end

  defp await_ready(_netlify, %{"state" => "ready"} = deploy, _attempts_left), do: live_url(deploy)

  defp await_ready(_netlify, %{"state" => state} = deploy, _attempts_left) when state in @failed_states do
    case deploy["error_message"] do
      message when is_binary(message) and message != "" -> failure(message)
      _none -> failure("deploy zakończył się błędem")
    end
  end

  defp await_ready(_netlify, _deploy, 0), do: failure("deploy nie zakończył się na czas")

  defp await_ready(netlify, %{"id" => deploy_id}, attempts_left) do
    Process.sleep(netlify.poll_interval_ms)

    case request(netlify.client, method: :get, url: "/api/v1/deploys/#{encode_segment(deploy_id)}") do
      {:ok, deploy} when is_map(deploy) -> await_ready(netlify, Map.put(deploy, "id", deploy_id), attempts_left - 1)
      {:ok, _body} -> failure("niepoprawna odpowiedź o stanie deployu")
      {:error, response} -> failure(response)
    end
  end

  defp live_url(deploy) do
    case deploy["ssl_url"] || deploy["url"] do
      url when is_binary(url) and url != "" -> {:ok, url}
      _missing -> failure("odpowiedź bez adresu strony")
    end
  end

  defp request(client, options) do
    case Req.request(client, options) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, %Req.Response{} = response} -> {:error, response}
      {:error, exception} -> {:error, exception}
    end
  end

  defp name_taken?(%Req.Response{status: 422, body: body}), do: mentions_subdomain?(body)
  defp name_taken?(_response), do: false

  defp mentions_subdomain?(body) when is_binary(body), do: String.contains?(body, "subdomain")
  defp mentions_subdomain?(body) when is_map(body), do: body |> Jason.encode!() |> mentions_subdomain?()
  defp mentions_subdomain?(_body), do: false

  defp random_suffix do
    @suffix_length
    |> :crypto.strong_rand_bytes()
    |> Base.encode32(case: :lower, padding: false)
    |> binary_part(0, @suffix_length)
  end

  defp encode_segment(segment), do: URI.encode(segment, &URI.char_unreserved?/1)

  defp failure(%Req.Response{status: 401}), do: failure("nieprawidłowy token")

  defp failure(%Req.Response{body: %{"message" => message}}) when is_binary(message) and message != "",
    do: failure(message)

  defp failure(%Req.Response{status: status}), do: failure("HTTP #{status}")
  defp failure(exception) when is_exception(exception), do: exception |> Exception.message() |> failure()
  defp failure(message) when is_binary(message), do: {:error, "Netlify: " <> message}

  defp without_token({:error, message}, token) when is_binary(message),
    do: {:error, String.replace(message, token, @hidden_token)}

  defp without_token(outcome, _token), do: outcome
end
