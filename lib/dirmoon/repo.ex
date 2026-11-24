defmodule Dirmoon.Repo do
  use Ecto.Repo,
    otp_app: :dirmoon,
    adapter: Ecto.Adapters.Postgres
end
