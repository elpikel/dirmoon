defmodule DirmoonWeb.UserLive.Login do
  @moduledoc """
  The sign-in page: an email gets a magic link, without revealing whether
  the email has a User. Signed-in users land here to re-authenticate.
  """
  use DirmoonWeb, :live_view

  alias Dirmoon.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <div class="flex flex-col gap-2">
        <h1 id="login-title" class="text-[26px] font-extrabold tracking-[-0.03em]">Zaloguj się</h1>
        <p :if={@current_scope} id="reauthenticate-notice" class="text-[15px] text-body">
          Aby zmienić ustawienia konta, zaloguj się ponownie.
        </p>
        <p :if={!@current_scope} class="text-[15px] text-body">
          Wyślemy Ci link logowania na e-mail. Nie masz jeszcze konta?
          <.link
            id="sign-up-link"
            href={~p"/" <> "#sign-up-form-hero"}
            class="font-semibold text-ink underline"
          >
            Załóż je
          </.link>
        </p>
      </div>

      <p
        :if={local_mail_adapter?()}
        id="local-mail-adapter-notice"
        class="rounded-control bg-page-alt px-4 py-3 text-[13px] text-body"
      >
        Lokalny adapter poczty: wysłane wiadomości zobaczysz w <.link
          href="/dev/mailbox"
          class="underline"
        >skrzynce deweloperskiej</.link>.
      </p>

      <.form
        for={@form}
        id="login-form"
        action={~p"/users/log-in"}
        phx-submit="submit_magic"
        class="flex flex-col gap-4"
      >
        <.input
          readonly={!!@current_scope}
          field={@form[:email]}
          type="email"
          label="E-mail"
          autocomplete="username"
          spellcheck="false"
          required
          phx-mounted={JS.focus()}
        />
        <.button id="login-submit" variant="dark" type="submit" class="w-full">
          Wyślij link logowania <span aria-hidden="true">→</span>
        </.button>
      </.form>
    </Layouts.auth>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email = get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])
    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form)}
  end

  @impl true
  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}"))
    end

    {:noreply,
     socket
     |> put_flash(:info, "Sprawdź skrzynkę: jeśli ten adres ma konto w dirmoon, wysłaliśmy na niego link logowania.")
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp local_mail_adapter? do
    Application.get_env(:dirmoon, Dirmoon.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
