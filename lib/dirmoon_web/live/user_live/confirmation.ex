defmodule DirmoonWeb.UserLive.Confirmation do
  @moduledoc """
  The page a magic link opens: the user confirms, and the form posts the
  token to `UserSessionController` to sign them in. A new user's first
  sign-in also confirms their account.
  """
  use DirmoonWeb, :live_view

  alias Dirmoon.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <div class="flex flex-col gap-2">
        <h1 id="confirmation-title" class="text-[26px] font-extrabold tracking-[-0.03em]">
          {if @user.confirmed_at, do: "Sign in", else: "Confirm your account"}
        </h1>
        <p class="text-[15px] break-words text-body">{@user.email}</p>
      </div>

      <.form
        for={@form}
        id="confirmation-form"
        phx-mounted={JS.focus_first()}
        phx-submit="submit"
        action={session_action(@user)}
        phx-trigger-action={@trigger_submit}
        class="flex flex-col gap-2"
      >
        <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
        <.input
          :if={!@current_scope}
          field={@form[:remember_me]}
          type="checkbox"
          label="Keep me signed in on this device"
        />
        <.button
          id="confirmation-submit"
          variant="dark"
          type="submit"
          class="w-full"
          phx-disable-with="Signing in…"
        >
          {if @user.confirmed_at, do: "Sign in", else: "Confirm and sign in"}
        </.button>
      </.form>
    </Layouts.auth>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if user = Accounts.get_user_by_magic_link_token(token) do
      form = to_form(%{"token" => token, "remember_me" => "true"}, as: "user")

      {:ok, assign(socket, user: user, form: form, trigger_submit: false), temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(:error, "The sign-in link is invalid or has expired.")
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end

  defp session_action(%{confirmed_at: nil}), do: ~p"/users/log-in?_action=confirmed"
  defp session_action(_confirmed_user), do: ~p"/users/log-in"
end
