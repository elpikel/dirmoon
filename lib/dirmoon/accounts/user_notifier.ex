defmodule Dirmoon.Accounts.UserNotifier do
  @moduledoc """
  The Polish emails dirmoon sends to a User: sign-in links and email-change links.
  """
  import Swoosh.Email

  alias Dirmoon.Accounts.User
  alias Dirmoon.Mailer

  @sender {"dirmoon", "contact@example.com"}

  @doc """
  Delivers the link that confirms a change of the user's email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Potwierdź nowy adres e-mail", """
    Cześć,

    aby zmienić adres e-mail w dirmoon, otwórz ten link:

    #{url}

    Jeśli to nie Ty prosisz o zmianę, zignoruj tę wiadomość.

    dirmoon
    """)
  end

  @doc """
  Delivers a sign-in link: a confirmation for a new user, a plain sign-in
  link for a confirmed one.
  """
  def deliver_login_instructions(%User{confirmed_at: nil} = user, url) do
    deliver(user.email, "Potwierdź konto w dirmoon", """
    Cześć,

    aby potwierdzić konto i zalogować się do dirmoon, otwórz ten link:

    #{url}

    Link jest ważny 15 minut. Jeśli nie zakładasz konta w dirmoon, zignoruj tę wiadomość.

    dirmoon
    """)
  end

  def deliver_login_instructions(%User{} = user, url) do
    deliver(user.email, "Twój link logowania do dirmoon", """
    Cześć,

    aby zalogować się do dirmoon, otwórz ten link:

    #{url}

    Link jest ważny 15 minut. Jeśli nie prosisz o logowanie, zignoruj tę wiadomość.

    dirmoon
    """)
  end

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from(@sender)
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end
end
