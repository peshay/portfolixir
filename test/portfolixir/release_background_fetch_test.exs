defmodule Portfolixir.ReleaseBackgroundFetchTest do
  # async: false -- it sets environment variables the whole VM reads.
  use ExUnit.Case, async: false

  alias Portfolixir.RuntimeConfig

  # What config/runtime.exs needs under :prod to evaluate at all, each a
  # synthetic value its own check accepts.
  @release_env %{
    "SECRET_KEY_BASE" => String.duplicate("k7Qm", 16),
    "PHX_HOST" => "portfolixir.example",
    "DATABASE_URL" => "ecto://portfolixir:synthetic@db.example/portfolixir_prod",
    "PORTFOLIXIR_API_TOKEN" => String.duplicate("t3Zx", 12)
  }

  # User story (#1026, Sprint 18 C5, decided by the plan's D-7):
  # As an operator whose host must not call out,
  # I want PORTFOLIXIR_BACKGROUND_FETCH=off to leave the release's scheduled
  # fetches off, as it already does in development,
  # so that the instance sends nothing out without a firewall rule.
  #
  # Acceptance criteria:
  # - With the switch off, the release's runtime configuration turns logo
  #   discovery, the quote sync and the FX sync off.
  # - Unset, or set to anything but an off word, the release keeps all three
  #   as config/prod.exs sets them: on. The switch can only turn fetching off.
  # - It reads the words development reads: 0, false, no and off, in any case,
  #   around any blank.
  test "the switch turns the release's logo discovery and quote and FX sync off" do
    assert prod_fetch() == %{logos: true, quotes: true, fx: true}

    for off <- ["off", "OFF", " no ", "false", "0"] do
      assert release_fetch(off) == %{logos: false, quotes: false, fx: false}, inspect(off)
    end

    for on <- [nil, "on", "yes", "1", ""] do
      assert release_fetch(on) == %{logos: nil, quotes: nil, fx: nil}, inspect(on)
    end
  end

  # - A Compose install sets it in .env: docker-compose.yml passes it to the
  #   release, and .env.example names it.
  test "Compose passes the switch from .env to the release" do
    assert File.read!("docker-compose.yml") =~
             "PORTFOLIXIR_BACKGROUND_FETCH: ${PORTFOLIXIR_BACKGROUND_FETCH:-}"

    assert File.read!(".env.example") =~ ~r/^PORTFOLIXIR_BACKGROUND_FETCH=$/m
  end

  test "the switch reads the words development reads" do
    for off <- ["off", "Off", "no", "false", "0", " off "],
        do: refute(RuntimeConfig.background_fetch?(off))

    for on <- [nil, "", "on", "yes", "true", "1"], do: assert(RuntimeConfig.background_fetch?(on))
  end

  # The three switches config/runtime.exs sets under :prod with
  # PORTFOLIXIR_BACKGROUND_FETCH at `value` (nil: unset); nil where it sets
  # none, leaving config/prod.exs's value.
  defp release_fetch(value) do
    with_env(Map.put(@release_env, "PORTFOLIXIR_BACKGROUND_FETCH", value), fn ->
      "config/runtime.exs"
      |> Config.Reader.read!(env: :prod, target: :host)
      |> Keyword.fetch!(:portfolixir)
      |> switches()
    end)
  end

  defp prod_fetch do
    "config/prod.exs"
    |> Config.Reader.read!(env: :prod, target: :host)
    |> Keyword.fetch!(:portfolixir)
    |> switches()
  end

  defp switches(config) do
    %{
      logos: Keyword.get(config, :enable_logo_discovery),
      quotes: config |> Keyword.get(Portfolixir.Catalog.QuoteSync, []) |> Keyword.get(:enabled?),
      fx: config |> Keyword.get(Portfolixir.Fx.RateSync, []) |> Keyword.get(:enabled?)
    }
  end

  defp with_env(env, fun) do
    previous = Map.new(env, fn {name, _value} -> {name, System.get_env(name)} end)

    try do
      Enum.each(env, fn {name, value} -> put_env(name, value) end)
      fun.()
    after
      Enum.each(previous, fn {name, value} -> put_env(name, value) end)
    end
  end

  defp put_env(name, nil), do: System.delete_env(name)
  defp put_env(name, value), do: System.put_env(name, value)
end
