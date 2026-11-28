defmodule Dirmoon.AccountsTest do
  use Dirmoon.DataCase, async: true

  import Dirmoon.AccountsHelpers
  import Swoosh.TestAssertions

  alias Dirmoon.Accounts
  alias Dirmoon.Accounts.Account
  alias Dirmoon.Accounts.Membership
  alias Dirmoon.Accounts.Scope
  alias Dirmoon.Accounts.User
  alias Dirmoon.Accounts.UserToken

  test "sign-up with a new email creates a User, an Account and their Membership" do
    email = unique_user_email()

    assert :ok = Accounts.sign_up(%{"email" => email}, &"/users/log-in/#{&1}")

    user = Accounts.get_user_by_email(email)
    assert [%Membership{account_id: account_id}] = Repo.all_by(Membership, user_id: user.id)
    assert %Account{} = Repo.get(Account, account_id)
  end

  test "sign-up leaves the new Account without Unpaid Access when new Accounts are not set to be unpaid" do
    email = unique_user_email()

    :ok = Accounts.sign_up(%{"email" => email}, &"/users/log-in/#{&1}")

    assert %Account{unpaid_access: false} = email |> Accounts.get_user_by_email() |> Accounts.account_for_user()
  end

  test "sign-up with a new email emails a sign-in link to that address" do
    email = unique_user_email()

    :ok = Accounts.sign_up(%{"email" => email}, &"[TOKEN]#{&1}[TOKEN]")

    assert_received {:email, %Swoosh.Email{to: [{_name, ^email}]} = sent_email}
    token = extract_user_token(fn _url -> {:ok, sent_email} end)
    assert %User{email: ^email} = Accounts.get_user_by_magic_link_token(token)
  end

  test "sign-up with an email that already has a User answers the same and emails a sign-in link to the existing user" do
    user = insert(:user)
    user_count = Repo.aggregate(User, :count)
    account_count = Repo.aggregate(Account, :count)

    assert :ok = Accounts.sign_up(%{"email" => user.email}, &"[TOKEN]#{&1}[TOKEN]")

    assert_received {:email, %Swoosh.Email{} = sent_email}
    assert sent_email.to == [{"", user.email}]
    token = extract_user_token(fn _url -> {:ok, sent_email} end)
    assert Accounts.get_user_by_magic_link_token(token).id == user.id
    assert Repo.aggregate(User, :count) == user_count
    assert Repo.aggregate(Account, :count) == account_count
  end

  test "sign-up with a known email in different case reaches the existing user" do
    user = insert(:user)

    assert :ok = Accounts.sign_up(%{"email" => String.upcase(user.email)}, &"/users/log-in/#{&1}")

    assert Repo.aggregate(User, :count) == 1
    assert_email_sent(subject: "Your dirmoon sign-in link")
  end

  test "sign-up with an invalid email returns an email error, creates nothing and sends nothing" do
    assert {:error, changeset} = Accounts.sign_up(%{"email" => "not an email"}, & &1)

    assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    assert Repo.aggregate(User, :count) == 0
    assert Repo.aggregate(Account, :count) == 0
    assert_no_email_sent()
  end

  test "create_user_with_account creates an unconfirmed User with an Account and their Membership" do
    email = unique_user_email()

    {:ok, user} = Accounts.create_user_with_account(%{email: email})

    assert user.email == email
    assert is_nil(user.confirmed_at)
    assert [%Membership{}] = Repo.all_by(Membership, user_id: user.id)
  end

  test "create_user_with_account requires an email" do
    {:error, changeset} = Accounts.create_user_with_account(%{})

    assert %{email: ["can't be blank"]} = errors_on(changeset)
  end

  test "create_user_with_account rejects an email without @ or with spaces" do
    {:error, changeset} = Accounts.create_user_with_account(%{email: "not valid"})

    assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
  end

  test "create_user_with_account rejects an email longer than 160 characters" do
    {:error, changeset} = Accounts.create_user_with_account(%{email: String.duplicate("db", 100)})

    assert "should be at most 160 character(s)" in errors_on(changeset).email
  end

  test "create_user_with_account rejects a taken email regardless of case and creates no Account" do
    %{email: email} = insert(:user)
    account_count = Repo.aggregate(Account, :count)

    {:error, changeset} = Accounts.create_user_with_account(%{email: email})
    assert "has already been taken" in errors_on(changeset).email

    {:error, changeset} = Accounts.create_user_with_account(%{email: String.upcase(email)})
    assert "has already been taken" in errors_on(changeset).email
    assert Repo.aggregate(Account, :count) == account_count
  end

  test "get_user_by_email finds a signed-up user and nothing for an unknown email" do
    %{id: id} = user = insert(:user)

    assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
    refute Accounts.get_user_by_email(unique_user_email())
  end

  test "account_for_user returns the Account of the user's first Membership" do
    user = insert(:user)
    first_account = Accounts.account_for_user(user)
    later_account = insert(:account)

    Repo.insert!(%Membership{
      account_id: later_account.id,
      user_id: user.id,
      inserted_at: DateTime.shift(DateTime.utc_now(:second), hour: 1)
    })

    assert Accounts.account_for_user(user).id == first_account.id
  end

  test "account_for_user returns nil for a user with no Membership" do
    user = insert(:user, memberships: [])

    assert Accounts.account_for_user(user) == nil
  end

  test "scope_for_user holds the user and the Account of their first Membership" do
    %{user: user, account: account} = insert(:membership)

    assert %Scope{user: %User{id: user_id}, account: %Account{id: account_id}} = Accounts.scope_for_user(user)
    assert user_id == user.id
    assert account_id == account.id
  end

  test "scope_for_user fails fast for a user with no Membership" do
    user = insert(:user, memberships: [])

    assert_raise FunctionClauseError, fn -> Accounts.scope_for_user(user) end
  end

  test "sudo_mode? holds only for a recent authentication" do
    now = DateTime.utc_now()

    assert Accounts.sudo_mode?(%User{authenticated_at: now})
    assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.shift(now, minute: -19)})
    refute Accounts.sudo_mode?(%User{authenticated_at: DateTime.shift(now, minute: -21)})
    refute Accounts.sudo_mode?(%User{authenticated_at: DateTime.shift(now, minute: -11)}, -10)
    refute Accounts.sudo_mode?(%User{})
  end

  test "change_user_email returns a changeset that requires an email" do
    assert %Ecto.Changeset{required: [:email]} = Accounts.change_user_email(%User{})
  end

  test "deliver_user_update_email_instructions stores a hashed email-change token for the current email" do
    user = insert(:user)
    current_email = unique_user_email()

    token =
      extract_user_token(fn url ->
        Accounts.deliver_user_update_email_instructions(user, current_email, url)
      end)

    {:ok, decoded_token} = Base.url_decode64(token, padding: false)
    user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, decoded_token))
    assert user_token.user_id == user.id
    assert user_token.sent_to == user.email
    assert user_token.context == "change:#{current_email}"
  end

  test "update_user_email changes the email with a valid token and uses the token up" do
    user = insert(:user)
    new_email = unique_user_email()

    token =
      extract_user_token(fn url ->
        Accounts.deliver_user_update_email_instructions(%{user | email: new_email}, user.email, url)
      end)

    assert {:ok, %User{email: ^new_email}} = Accounts.update_user_email(user, token)
    assert Repo.get!(User, user.id).email == new_email
    refute Repo.get_by(UserToken, user_id: user.id)
  end

  test "update_user_email keeps the email for an invalid token" do
    user = insert(:user)
    _token = generate_user_magic_link_token(user)

    assert Accounts.update_user_email(user, "oops") == {:error, :transaction_aborted}
    assert Repo.get!(User, user.id).email == user.email
  end

  test "update_user_email keeps the email when the user's email changed since the link was sent" do
    user = insert(:user)
    current_email = unique_user_email()

    token =
      extract_user_token(fn url ->
        Accounts.deliver_user_update_email_instructions(%{user | email: unique_user_email()}, user.email, url)
      end)

    assert Accounts.update_user_email(%{user | email: current_email}, token) ==
             {:error, :transaction_aborted}

    assert Repo.get!(User, user.id).email == user.email
    assert Repo.get_by(UserToken, user_id: user.id)
  end

  test "update_user_email keeps the email for an expired token" do
    user = insert(:user)

    token =
      extract_user_token(fn url ->
        Accounts.deliver_user_update_email_instructions(%{user | email: unique_user_email()}, user.email, url)
      end)

    {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

    assert Accounts.update_user_email(user, token) == {:error, :transaction_aborted}
    assert Repo.get!(User, user.id).email == user.email
  end

  test "generate_user_session_token stores a unique session token" do
    user = insert(:user)
    other_user = insert(:user)

    token = Accounts.generate_user_session_token(user)

    user_token = Repo.get_by(UserToken, token: token)
    assert user_token.context == "session"
    assert user_token.authenticated_at

    assert_raise Ecto.ConstraintError, fn ->
      Repo.insert!(%UserToken{token: user_token.token, user_id: other_user.id, context: "session"})
    end
  end

  test "generate_user_session_token carries the user's authenticated_at into the token" do
    authenticated_at = DateTime.shift(DateTime.utc_now(:second), hour: -1)
    user = %{insert(:user) | authenticated_at: authenticated_at}

    token = Accounts.generate_user_session_token(user)

    user_token = Repo.get_by(UserToken, token: token)
    assert user_token.authenticated_at == authenticated_at
    assert DateTime.after?(user_token.inserted_at, authenticated_at)
  end

  test "get_user_by_session_token returns the user with their sign-in time" do
    user = insert(:user)
    token = Accounts.generate_user_session_token(user)

    assert {session_user, token_inserted_at} = Accounts.get_user_by_session_token(token)
    assert session_user.id == user.id
    assert session_user.authenticated_at
    assert token_inserted_at
  end

  test "get_user_by_session_token returns nothing for an invalid token" do
    refute Accounts.get_user_by_session_token("oops")
  end

  test "get_user_by_session_token returns nothing for an expired token" do
    token = :user |> insert() |> Accounts.generate_user_session_token()
    offset_user_token(token, -15, :day)

    refute Accounts.get_user_by_session_token(token)
  end

  test "get_user_by_magic_link_token returns the user of a valid token" do
    user = insert(:user)
    %{token: token} = generate_user_magic_link_token(user)

    assert Accounts.get_user_by_magic_link_token(token).id == user.id
  end

  test "get_user_by_magic_link_token returns nothing for an invalid token" do
    refute Accounts.get_user_by_magic_link_token("oops")
  end

  test "get_user_by_magic_link_token returns nothing for an expired token" do
    %{token: token, hashed_token: hashed_token} = :user |> insert() |> generate_user_magic_link_token()
    offset_user_token(hashed_token, -16, :minute)

    refute Accounts.get_user_by_magic_link_token(token)
  end

  test "login_user_by_magic_link confirms an unconfirmed user and expires all their tokens" do
    user = insert(:user, confirmed_at: nil)
    %{token: token, hashed_token: hashed_token} = generate_user_magic_link_token(user)

    assert {:ok, {user, [%{token: ^hashed_token}]}} = Accounts.login_user_by_magic_link(token)
    assert user.confirmed_at
    refute Repo.get_by(UserToken, user_id: user.id)
  end

  test "login_user_by_magic_link signs a confirmed user in once per link" do
    user = insert(:user)
    %{token: token} = generate_user_magic_link_token(user)

    assert {:ok, {signed_in_user, []}} = Accounts.login_user_by_magic_link(token)
    assert signed_in_user.id == user.id
    assert {:error, :not_found} = Accounts.login_user_by_magic_link(token)
  end

  test "login_user_by_magic_link rejects a malformed token" do
    assert {:error, :not_found} = Accounts.login_user_by_magic_link("not base64 !")
  end

  test "delete_user_session_token ends the session" do
    token = :user |> insert() |> Accounts.generate_user_session_token()

    assert Accounts.delete_user_session_token(token) == :ok
    refute Accounts.get_user_by_session_token(token)
  end

  test "deliver_login_instructions stores a hashed login token sent to the user's email" do
    user = insert(:user, confirmed_at: nil)

    token = extract_user_token(fn url -> Accounts.deliver_login_instructions(user, url) end)

    {:ok, decoded_token} = Base.url_decode64(token, padding: false)
    user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, decoded_token))
    assert user_token.user_id == user.id
    assert user_token.sent_to == user.email
    assert user_token.context == "login"
  end

  test "sign-in emails come from dirmoon in English" do
    user = insert(:user, confirmed_at: nil)

    {:ok, email} = Accounts.deliver_login_instructions(user, &"/users/log-in/#{&1}")

    assert email.from == {"dirmoon", "contact@example.com"}
    assert email.subject == "Confirm your dirmoon account"
    assert email.text_body =~ "to confirm your account and sign in to dirmoon"
  end
end
