defmodule Portfolixir.Repo do
  use Ecto.Repo,
    otp_app: :portfolixir,
    adapter: Ecto.Adapters.Postgres
end
