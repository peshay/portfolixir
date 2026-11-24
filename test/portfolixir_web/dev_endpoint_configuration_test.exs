defmodule PortfolixirWeb.DevEndpointConfigurationTest do
  # async: false -- it reads the configuration files under an environment it
  # sets and restores, and starts endpoints of its own.
  use ExUnit.Case, async: false

  import Plug.Conn, only: [put_req_header: 3]

  alias Portfolixir.RuntimeConfig

  @endpoint_mod PortfolixirWeb.Endpoint
  @switch "PORTFOLIXIR_DEV_DEBUG_ERRORS"
  @sound_key String.duplicate("k7Qm", 16)
  @probe_key String.duplicate("p4Xz", 16)

  # User story (security review 2026-11, N-01):
  # As an operator who runs Portfolixir from source,
  # I want the development configuration to serve no debug pages and to sign
  # with a key that is not in the repository,
  # so that the UI password locks that route as the README says it does.
  #
  # Acceptance criteria:
  # - config/dev.exs leaves `debug_errors` off unless PORTFOLIXIR_DEV_DEBUG_ERRORS
  #   switches it on, in the release's switch vocabulary.
  # - An endpoint compiled with that default has no debugger route: a request
  #   to the debugger's action path reaches the endpoint's own pipeline.
  # - No configuration file gives the development endpoint a signing key.
  #   config/runtime.exs takes it, under :dev, from SECRET_KEY_BASE by the
  #   release's rules, or from a file generated per checkout that git does
  #   not track, and derives the LiveView salt from it.
  # - The README, SECURITY.md, llms.txt and the deployment guides say so.
  describe "debug pages" do
    test "config/dev.exs leaves them off unless the developer switch asks" do
      assert dev_endpoint(%{@switch => nil})[:debug_errors] == false

      for off <- ["", " ", "0", "false", "no", "off", "OFF", "debug", "2"] do
        assert dev_endpoint(%{@switch => off})[:debug_errors] == false,
               "#{@switch}=#{inspect(off)} switched debug pages on"
      end

      for on <- ["1", "true", "yes", "on", " ON ", "True"] do
        assert dev_endpoint(%{@switch => on})[:debug_errors] == true,
               "#{@switch}=#{inspect(on)} left debug pages off"
      end
    end

    test "an endpoint compiled with the development default has no debugger route" do
      default = dev_endpoint(%{@switch => nil})[:debug_errors]
      probe = start_probe!(PortfolixirWeb.DevDefaultEndpointProbe, default)

      conn = debugger_action(probe)

      assert conn.status == 404
      assert conn.resp_body == "the endpoint's own pipeline"
      refute_received :debugger_action_ran
    end

    test "control: with the developer switch on, that path is the debugger's" do
      switched = dev_endpoint(%{@switch => "on"})[:debug_errors]
      probe = start_probe!(PortfolixirWeb.DevSwitchedEndpointProbe, switched)

      conn = debugger_action(probe)

      assert conn.status == 302
      assert_received :debugger_action_ran
    end
  end

  describe "the signing key" do
    test "no configuration file gives the development endpoint one" do
      dev = dev_endpoint(%{})

      refute Keyword.has_key?(dev, :secret_key_base)
      refute Keyword.has_key?(dev, :live_view)

      # Whatever a file evaluates to is in the repository; a literal spelled
      # out in it is too.
      for path <- ["config/dev.exs", "config/runtime.exs"] do
        refute File.read!(path) =~ ~r/secret_key_base\w*:?\s*=?\s*\n?\s*"/,
               "#{path} assigns a signing key literal"
      end
    end

    test "config/runtime.exs takes it under :dev from SECRET_KEY_BASE, by the release's rules" do
      endpoint = runtime_dev_endpoint(%{"SECRET_KEY_BASE" => @sound_key})

      assert endpoint[:secret_key_base] == @sound_key

      assert endpoint[:live_view] == [
               signing_salt: RuntimeConfig.derived_salt(@sound_key, "live_view")
             ]

      for refused <- [
            binary_part(@sound_key, 0, 63),
            String.pad_trailing("replace-with-openssl-rand-base64-48", 64, "x"),
            "dev_secret_key_base_which_should_be_changed_in_production_and_is_long_enough_for_sessions"
          ] do
        assert_raise ArgumentError, ~r/SECRET_KEY_BASE/, fn ->
          runtime_dev_endpoint(%{"SECRET_KEY_BASE" => refused})
        end
      end

      assert File.read!("config/runtime.exs") =~
               ~s{RuntimeConfig.dev_secret_key_base!(System.get_env("SECRET_KEY_BASE"))}
    end

    test "without SECRET_KEY_BASE it is generated once per checkout, for its owner only" do
      tmp_dir = tmp_dir!()
      path = Path.join([tmp_dir, "build", "dev_secret_key_base"])

      for unset <- [nil, "", "  "] do
        key = RuntimeConfig.dev_secret_key_base!(unset, path)

        assert byte_size(key) >= 64
        assert key == String.trim(File.read!(path))
        # The same key on every start: a restart ends no session.
        assert RuntimeConfig.dev_secret_key_base!(unset, path) == key
      end

      assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600

      other = Path.join([tmp_dir, "another-checkout", "dev_secret_key_base"])
      refute RuntimeConfig.dev_secret_key_base!(nil, other) == File.read!(path)

      # An exported key wins and writes nothing.
      exported = Path.join(tmp_dir, "never-written")
      assert RuntimeConfig.dev_secret_key_base!(@sound_key, exported) == @sound_key
      refute File.exists?(exported)
    end

    test "a stored key that is too short is refused, naming the file" do
      tmp_dir = tmp_dir!()
      path = Path.join(tmp_dir, "dev_secret_key_base")
      File.write!(path, "short\n")

      error =
        assert_raise ArgumentError, fn -> RuntimeConfig.dev_secret_key_base!(nil, path) end

      assert error.message =~ path
      assert error.message =~ "SECRET_KEY_BASE"
    end

    test "the generated key lives where git and the image build never look" do
      path = RuntimeConfig.dev_secret_key_base_path()

      assert path == "_build/dev_secret_key_base"

      for ignore <- [".gitignore", ".dockerignore"] do
        assert ignore |> File.read!() |> String.split("\n") |> Enum.member?("/_build/"),
               "#{ignore} no longer leaves out /_build/, where #{path} is written"
      end
    end
  end

  test "the documents say what the development configuration signs with and serves" do
    flat = fn path -> path |> File.read!() |> String.replace(~r/\s+/, " ") end

    readme = flat.("README.md")
    assert readme =~ "`_build/dev_secret_key_base`"
    assert readme =~ "`#{@switch}=on`"
    refute readme =~ "a key the repository publishes"

    security = flat.("SECURITY.md")
    assert security =~ "`_build/dev_secret_key_base`"
    assert security =~ "`#{@switch}`"
    refute security =~ "`SECRET_KEY_BASE` committed in `config/dev.exs`"
    refute security =~ "the same public session key"

    refute flat.("docs/llms.txt") =~ "session key is public"

    for path <- [
          "docs/home-deployment.md",
          "docs/de/home-deployment.md",
          "docker-compose.dev.yml"
        ] do
      text = flat.(path)
      refute text =~ "public session key", path
      refute text =~ "öffentlicher Sitzungsschlüssel", path
      refute text =~ "committed in `config/dev.exs`", path
      refute text =~ "eingecheckten `SECRET_KEY_BASE`", path
    end
  end

  # -- helpers -----------------------------------------------------------------

  # A directory of the test's own outside the checkout, removed afterwards.
  defp tmp_dir! do
    dir =
      Path.join(System.tmp_dir!(), "dev-signing-key-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  # What config/dev.exs evaluates to for the endpoint under the given
  # environment (nil unsets a variable); the environment is restored.
  defp dev_endpoint(env) do
    with_env(Map.put_new(env, @switch, nil), fn ->
      "config/dev.exs"
      |> Config.Reader.read!(env: :dev, target: :host)
      |> Keyword.fetch!(:portfolixir)
      |> Keyword.fetch!(@endpoint_mod)
    end)
  end

  defp runtime_dev_endpoint(env) do
    with_env(env, fn ->
      "config/runtime.exs"
      |> Config.Reader.read!(env: :dev, target: :host)
      |> Keyword.fetch!(:portfolixir)
      |> Keyword.fetch!(@endpoint_mod)
    end)
  end

  defp with_env(env, fun) do
    saved = for {name, _value} <- env, do: {name, System.get_env(name)}

    try do
      for {name, value} <- env do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end

      fun.()
    after
      for {name, value} <- saved do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end
    end
  end

  # An endpoint compiled the way Phoenix compiles PortfolixirWeb.Endpoint: the
  # flag is read when the module is compiled, so the probe is compiled here,
  # with the value the development configuration gave it.
  defp start_probe!(name, debug_errors) do
    Application.put_env(:portfolixir, name,
      debug_errors: debug_errors,
      secret_key_base: @probe_key,
      server: false
    )

    on_exit(fn -> Application.delete_env(:portfolixir, name) end)

    Code.compile_quoted(
      quote do
        defmodule unquote(name) do
          use Phoenix.Endpoint, otp_app: :portfolixir

          plug(:answer)

          def answer(conn, _opts),
            do: Plug.Conn.send_resp(conn, 404, "the endpoint's own pipeline")
        end
      end
    )

    start_supervised!(name)
    name
  end

  # The debugger's own action request, signed with the probe's own key.
  defp debugger_action(probe) do
    handler = {Kernel, :send, [self(), :debugger_action_ran]}
    token = Plug.Crypto.sign(@probe_key, "plug-debugger-actions", handler)

    :post
    |> Plug.Test.conn(
      "/__plug__/debugger/action",
      "encoded_handler=" <> URI.encode_www_form(token)
    )
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> probe.call(probe.init([]))
  end
end
