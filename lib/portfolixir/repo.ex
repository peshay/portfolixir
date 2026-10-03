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

  # Ecto runs the preloads of a read outside a transaction in tasks of their
  # own, each checking out a connection. Under the test sandbox every query of
  # a test runs on the test's one connection, so those tasks can only queue
  # for it, and under load the queue dropped one of them (#1018). The test
  # configuration (`preload_in_parallel: false`) preloads on the calling
  # process; everywhere else Ecto's default stands.
  unless Application.compile_env(:portfolixir, :preload_in_parallel, true) do
    @impl true
    def default_options(operation) when operation in [:all, :preload, :reload, :stream],
      do: [in_parallel: false]

    def default_options(_operation), do: []
  end
end
