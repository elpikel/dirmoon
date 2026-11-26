defmodule Dirmoon.Accounts.UserNotifier do
  @moduledoc """
  The emails dirmoon sends to a User: sign-in links and email-change links.
  """
  import Swoosh.Email

  alias Dirmoon.Accounts.User
  alias Dirmoon.Mailer

  @doc """
  Delivers the link that confirms a change of the user's email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Confirm your new email address", """
    Hi,

    to change your email address in dirmoon, open this link:

    #{url}

    If you didn't ask for this change, ignore this email.

    dirmoon
    """)
  end

  @doc """
  Delivers a sign-in link: a confirmation for a new user, a plain sign-in
  link for a confirmed one.
  """
  def deliver_login_instructions(%User{confirmed_at: nil} = user, url) do
    deliver(user.email, "Confirm your dirmoon account", """
    Hi,

    to confirm your account and sign in to dirmoon, open this link:

    #{url}

    The link works for 15 minutes. If you didn't create a dirmoon account, ignore this email.

    dirmoon
    """)
  end

  def deliver_login_instructions(%User{} = user, url) do
    deliver(user.email, "Your dirmoon sign-in link", """
    Hi,

    to sign in to dirmoon, open this link:

    #{url}

    The link works for 15 minutes. If you didn't ask to sign in, ignore this email.

    dirmoon
    """)
  end

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"dirmoon", Application.fetch_env!(:dirmoon, :mail_from)})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end
end
