defmodule Portfolixir.ReleaseDatabasePasswordTest do
  # The database password is a secret on every documented route (security
  # review 2026-10-12, H18). config/runtime.exs and config/dev.exs are
  # evaluated with Config.Reader, and Compose's interpolation is emulated
  # and, where the docker CLI is installed, cross-checked with
  # `docker compose config`, which reads files only. No network, no database.
  #
  # async: false -- it sets environment variables the whole VM reads and
  # restores every one of them.
  use ExUnit.Case, async: false

  @compose "docker-compose.yml"
  @env_example ".env.example"
  @runtime "config/runtime.exs"
  @dev "config/dev.exs"
  @security "SECURITY.md"

  # User story (security review 2026-10-12, H18):
  # As the operator who copies .env.example for the Compose deployment,
  # I want the stack unable to start on the database password it ships,
  # so that the bootstrap superuser never runs on a string printed in the
  # repository.
  #
  # Acceptance criteria:
  # - Compose refuses the shipped POSTGRES_PASSWORD, or the release refuses
  #   to boot on it while it boots on a generated one and refuses the other
  #   shipped placeholders.
  test "the POSTGRES_PASSWORD .env.example ships cannot start the Compose release" do
    shipped = env_example_value!("POSTGRES_PASSWORD")

    case compose_database_url(shipped) do
      {:refused, _reason} ->
        # Shipped empty: Compose's ${POSTGRES_PASSWORD:?...} stops the stack.
        :ok

      {:ok, database_url} ->
        compose_cli_cross_check(shipped, database_url)

        # Controls: the same harness refuses the other placeholders
        # .env.example ships, and boots with a generated database password.
        {:ok, sound_url} = compose_database_url(hex(32))

        assert {:refused, skb} =
                 boot(sound_url, secret_key_base: env_example_value!("SECRET_KEY_BASE"))

        assert skb =~ "SECRET_KEY_BASE"

        assert {:refused, token} =
                 boot(sound_url, api_token: env_example_value!("PORTFOLIXIR_API_TOKEN"))

        assert token =~ "PORTFOLIXIR_API_TOKEN"

        assert {:ok, _config} = boot(sound_url)

        # Every other secret sound, the shipped database password must not
        # boot the release.
        result = boot(database_url)

        repo_url =
          case result do
            {:ok, config} ->
              config
              |> Keyword.fetch!(:portfolixir)
              |> Keyword.fetch!(Portfolixir.Repo)
              |> Keyword.get(:url)

            {:refused, _} ->
              nil
          end

        assert match?({:refused, _}, result),
               "the release booted on the POSTGRES_PASSWORD .env.example ships " <>
                 "(#{inspect(shipped)}), with Repo url #{inspect(repo_url)}"
    end
  end

  # User story (security review 2026-10-12, H18):
  # As an operator who runs the instance from source,
  # I want the database login that route uses either mine to choose or
  # stated in SECURITY.md where the development stack's is,
  # so that I know what the route's posture is before I trust it with real
  # records.
  #
  # Acceptance criteria:
  # - config/dev.exs takes DATABASE_USER and DATABASE_PASSWORD when set, or a
  #   SECURITY.md paragraph names the password `postgres` for the route run
  #   from source.
  test "the from-source route's database login is configurable or stated in SECURITY.md" do
    user = "h18_" <> hex(4)
    password = hex(32)

    repo =
      with_env(%{"DATABASE_USER" => user, "DATABASE_PASSWORD" => password}, fn ->
        @dev
        |> Config.Reader.read!(env: :dev, target: :host)
        |> Keyword.fetch!(:portfolixir)
        |> Keyword.fetch!(Portfolixir.Repo)
      end)

    configurable? = repo[:username] == user and repo[:password] == password

    # Or SECURITY.md states the from-source route's public database password
    # where it states the development stack's.
    acknowledged? =
      @security
      |> File.read!()
      |> String.split(~r/\n[ \t]*\n/)
      |> Enum.any?(fn paragraph ->
        paragraph =~ "password `postgres`" and
          paragraph =~ ~r/run from source|from-source|mix phx\.server/i
      end)

    assert configurable? or acknowledged?,
           "config/dev.exs connects as #{inspect(repo[:username])} with DATABASE_USER and " <>
             "DATABASE_PASSWORD set, and no SECURITY.md paragraph states the from-source " <>
             "route's database password"
  end

  # User story (security review 2026-10-12, H18):
  # As the operator of a release,
  # I want it to refuse to boot on an empty, placeholder or short database
  # password, naming the variable and never the value,
  # so that a forgotten replacement is reported instead of run.
  #
  # Acceptance criteria:
  # - A DATABASE_URL with no password, an empty one, a placeholder or one
  #   shorter than the floor stops the boot; the message names
  #   POSTGRES_PASSWORD and DATABASE_URL and never carries the password.
  # - A generated hex password boots.
  test "a release refuses an empty, placeholder or short database password, naming the variable" do
    for password <- [nil, "", "replace-with-openssl-rand-hex-32", "postgres", "Short-Pw-1234"] do
      userinfo = if password, do: "portfolixir:" <> password, else: "portfolixir"
      url = "postgres://#{userinfo}@db:5432/portfolixir_prod"

      assert {:refused, message} = boot(url), inspect(password)
      assert message =~ "POSTGRES_PASSWORD"
      assert message =~ "DATABASE_URL"
      if password not in [nil, ""], do: refute(message =~ password)
    end

    assert {:ok, _config} = boot("postgres://portfolixir:#{hex(32)}@db:5432/portfolixir_prod")
  end

  # --- Compose -------------------------------------------------------------

  # docker-compose.yml's app DATABASE_URL, interpolated as Compose does:
  # ${NAME:?message} is an error when NAME is unset or empty, ${NAME?message}
  # when it is unset, and otherwise the value.
  defp compose_database_url(password) do
    compose = File.read!(@compose)

    [_, template] =
      Regex.run(~r/^\s+DATABASE_URL: (.+)$/m, compose) ||
        flunk("#{@compose} has no DATABASE_URL line")

    placeholder = ~r/\$\{POSTGRES_PASSWORD(?:(:?\?)([^}]*))?\}/

    case Regex.run(placeholder, template) do
      nil ->
        flunk("#{@compose}'s DATABASE_URL no longer interpolates POSTGRES_PASSWORD")

      [_whole, ":?", message] when password in [nil, ""] ->
        {:refused, message}

      [_whole, "?", message] when is_nil(password) ->
        {:refused, message}

      _other ->
        {:ok, Regex.replace(placeholder, template, fn _ -> password || "" end, global: false)}
    end
  end

  # When the docker CLI is present, Compose itself interpolates the file (no
  # daemon needed) with the four required secrets: the database one as
  # shipped, the three refused ones generated. --env-file /dev/null keeps any
  # .env in the checkout out of it.
  defp compose_cli_cross_check(shipped, expected_url) do
    with docker when is_binary(docker) <- System.find_executable("docker"),
         {_, 0} <- System.cmd(docker, ["compose", "version"], stderr_to_stdout: true) do
      env = [
        {"POSTGRES_PASSWORD", shipped},
        {"SECRET_KEY_BASE", base64(48)},
        {"PORTFOLIXIR_API_TOKEN", base64(48)},
        {"PORTFOLIXIR_MCP_TOKEN", base64(48)}
      ]

      {out, status} =
        System.cmd(
          docker,
          ["compose", "--env-file", "/dev/null", "-f", @compose, "config", "--format", "json"],
          env: env,
          stderr_to_stdout: false
        )

      assert status == 0, "docker compose config refused the shipped POSTGRES_PASSWORD: #{out}"

      services = out |> Jason.decode!() |> Map.fetch!("services")
      assert get_in(services, ["app", "environment", "DATABASE_URL"]) == expected_url
      assert get_in(services, ["db", "environment", "POSTGRES_PASSWORD"]) == shipped
    else
      _ -> :no_docker_cli
    end
  end

  # --- The release's boot checks ---------------------------------------------

  # config/runtime.exs under :prod with the environment docker-compose.yml
  # hands the app service (.env.example's values for the optional settings),
  # the secrets generated unless overridden. {:ok, config} or
  # {:refused, message}.
  defp boot(database_url, overrides \\ []) do
    env = %{
      "DATABASE_URL" => database_url,
      "SECRET_KEY_BASE" => Keyword.get(overrides, :secret_key_base, base64(48)),
      "PORTFOLIXIR_API_TOKEN" => Keyword.get(overrides, :api_token, base64(48)),
      "PORTFOLIXIR_API_PRINCIPAL" => "mcp",
      "PORTFOLIXIR_API_TOKENS" => "",
      "PHX_HOST" => "localhost",
      "PORTFOLIXIR_ALLOWED_HOSTS" => "app,",
      "PHX_FORCE_SSL" => "false",
      "PORTFOLIXIR_FORCE_SSL_EXCLUDED_HOSTS" => "app",
      "PORTFOLIXIR_TRUSTED_PROXIES" => "",
      "PHX_BIND_ALL" => "true",
      "PORT" => "4000",
      "PORTFOLIXIR_BACKGROUND_FETCH" => "",
      # Dockerfile.release sets it for the release image.
      "PORTFOLIXIR_LOGO_DIR" => "/var/lib/portfolixir/logos",
      "DATABASE_SSL" => nil,
      "POOL_SIZE" => nil
    }

    with_env(env, fn ->
      try do
        {:ok, Config.Reader.read!(@runtime, env: :prod, target: :host)}
      rescue
        error -> {:refused, Exception.message(error)}
      end
    end)
  end

  # --- Helpers ----------------------------------------------------------------

  defp env_example_value!(name) do
    case Regex.run(~r/^#{name}=(.*)$/m, File.read!(@env_example)) do
      [_, value] -> String.trim(value)
      nil -> flunk("#{@env_example} no longer names #{name}")
    end
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

  defp hex(bytes), do: Base.encode16(:crypto.strong_rand_bytes(bytes), case: :lower)
  defp base64(bytes), do: Base.encode64(:crypto.strong_rand_bytes(bytes))
end
