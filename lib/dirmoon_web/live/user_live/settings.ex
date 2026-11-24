defmodule DirmoonWeb.UserLive.Settings do
  @moduledoc """
  Account settings: changing the sign-in email, confirmed through a link sent
  to the new address. Requires a recent sign-in (sudo mode).
  """
  use DirmoonWeb, :live_view

  alias Dirmoon.Accounts

  on_mount {DirmoonWeb.UserAuth, :require_sudo_mode}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="settings" class="flex w-full max-w-[640px] flex-col gap-7">
        <div class="flex flex-col gap-2">
          <h1 id="settings-title" class="text-[30px] font-extrabold tracking-[-0.03em]">
            Ustawienia
          </h1>
          <p class="text-[15px] text-body">Adres e-mail, na który wysyłamy linki logowania.</p>
        </div>

        <.form
          for={@email_form}
          id="email-form"
          phx-submit="update_email"
          phx-change="validate_email"
          class="flex flex-col items-start gap-4 [&>div]:w-full"
        >
          <.input
            field={@email_form[:email]}
            type="email"
            label="E-mail"
            autocomplete="username"
            spellcheck="false"
            required
          />
          <.button id="email-submit" variant="dark" type="submit" phx-disable-with="Zapisuję…">
            Zmień e-mail
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} -> put_flash(socket, :info, "Adres e-mail zmieniony.")
        {:error, _reason} -> put_flash(socket, :error, "Link zmiany adresu jest nieprawidłowy albo wygasł.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    email_changeset = Accounts.change_user_email(socket.assigns.current_scope.user, %{}, validate_unique: false)

    {:ok, assign(socket, :email_form, to_form(email_changeset))}
  end

  @impl true
  def handle_event("validate_email", %{"user" => user_params}, socket) do
    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> to_form(action: :validate)

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", %{"user" => user_params}, socket) do
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params, validate_unique: false) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        {:noreply, put_flash(socket, :info, "Wysłaliśmy link potwierdzający na nowy adres.")}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end
end
