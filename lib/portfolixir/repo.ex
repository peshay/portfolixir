defmodule Portfolixir.Repo do
  use Ecto.Repo,
    otp_app: :portfolixir,
    adapter: Ecto.Adapters.Postgres

  # Every connection takes the host clock's zone, so the database's
  # CURRENT_DATE is the day Portfolixir.Clock.today/0 decides with
  # (E25 S6, G08).
  @impl true
  def init(_context, config) do
    {:ok,
     Keyword.put_new(config, :after_connect, {Portfolixir.Repo.SessionZone, :after_connect, []})}
  end
end
