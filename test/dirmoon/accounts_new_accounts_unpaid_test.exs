defmodule Dirmoon.AccountsNewAccountsUnpaidTest do
  use Dirmoon.DataCase, async: false

  alias Dirmoon.Accounts
  alias Dirmoon.Accounts.Account

  test "sign-up marks the new Account Unpaid Access when new Accounts are set to be unpaid" do
    configured = Application.fetch_env!(:dirmoon, Accounts)
    Application.put_env(:dirmoon, Accounts, Keyword.put(configured, :new_accounts_unpaid, true))
    on_exit(fn -> Application.put_env(:dirmoon, Accounts, configured) end)
    email = unique_user_email()

    :ok = Accounts.sign_up(%{"email" => email}, &"/users/log-in/#{&1}")

    assert %Account{unpaid_access: true} = email |> Accounts.get_user_by_email() |> Accounts.account_for_user()
  end
end
