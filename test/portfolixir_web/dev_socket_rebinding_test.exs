defmodule PortfolixirWeb.DevSocketRebindingTest do
  # async: false -- it patches the shared endpoint's runtime config (restored
  # on exit) and needs the sandbox in shared mode for the LiveView process.
  use PortfolixirWeb.ConnCase, async: false

  import Ecto.Query, only: [from: 2]
  import ExUnit.CaptureLog

  alias Phoenix.LiveView.Static
  alias Plug.Session.COOKIE
  alias Portfolixir.Buckets
  alias Portfolixir.Buckets.Bucket
  alias Portfolixir.Repo
  alias Portfolixir.RuntimeConfig
  alias Portfolixir.WorldFixtures

  @root "."
  @endpoint_mod PortfolixirWeb.Endpoint
  @attacker_host "rebind.attacker.example"
  @depot_marker "Synthetic Rebind Probe Depot"
  @cash_marker "Synthetic Rebind Probe Cash"
  @planted_tag "Synthetic planted tag"

  setup do
    dev = dev_endpoint_security_config()

    # The precondition the finding names: no UI password on the route.
    saved_app_pw = Application.get_env(:portfolixir, :ui_password)
    saved_env_pw = System.get_env("PORTFOLIXIR_UI_PASSWORD")
    Application.delete_env(:portfolixir, :ui_password)
    System.delete_env("PORTFOLIXIR_UI_PASSWORD")

    saved_endpoint =
      for key <- [:check_origin, :secret_key_base, :live_view] do
        {key, :ets.lookup(@endpoint_mod, key)}
      end

    on_exit(fn ->
      for {key, saved} <- saved_endpoint do
        case saved do
          [{^key, value}] -> :ets.insert(@endpoint_mod, {key, value})
          [] -> :ets.delete(@endpoint_mod, key)
        end
      end

      Phoenix.Config.clear_cache(@endpoint_mod)

      if saved_app_pw,
        do: Application.put_env(:portfolixir, :ui_password, saved_app_pw),
        else: Application.delete_env(:portfolixir, :ui_password)

      if saved_env_pw,
        do: System.put_env("PORTFOLIXIR_UI_PASSWORD", saved_env_pw),
        else: System.delete_env("PORTFOLIXIR_UI_PASSWORD")
    end)

    world =
      WorldFixtures.base_world(
        name: "Synthetic Rebind Portfolio",
        depot_name: @depot_marker,
        cash_name: @cash_marker
      )

    server =
      start_supervised!(
        {Bandit,
         plug: @endpoint_mod, scheme: :http, ip: {127, 0, 0, 1}, port: 0, startup_log: false}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    {:ok, dev: dev, world: world, port: port}
  end

  # User story (security review 2026-10-12, K18):
  # As an operator who runs Portfolixir from source,
  # I want the development server's live socket to accept only the names its
  # Host guard accepts, and its signing salts derived from its secret as a
  # release derives them,
  # so that a website I open cannot reach my records through that socket.
  #
  # Acceptance criteria:
  # - A socket handshake under a foreign origin, with a session cookie and a
  #   LiveView token forged from what the repository prints, reads and
  #   writes nothing.
  # - The development configuration's socket origins are the Host guard's
  #   names, each as `//host`, never `false`; its LiveView salt is derived
  #   from its secret, not a literal committed in the configuration.
  # - With the origin check open, the UI password still refuses the forged
  #   session at mount (the control behind the README's requirement).
  # - The README and llms.txt require the UI password on the run-from-source
  #   route.
  test "a DNS-rebinding page cannot read or write through the /live socket of a from-source instance",
       %{dev: dev, world: world, port: port} do
    # The server runs with what config/*.exs evaluate to under :dev; the
    # attacker forges with what the repository's files print (attacker/0).
    apply_endpoint_config(dev)

    {result, log} = with_log(fn -> rebinding_attack(attacker(dev), world, port) end)

    route =
      "config/dev.exs check_origin=#{inspect(dev.check_origin)}; runtime.exs under :dev " <>
        "touches the endpoint: #{dev.runtime_dev_touches_endpoint?}; live_view salt is a " <>
        "committed literal: #{dev.live_view_salt in committed_literal_salts()}; " <>
        "secret_key_base is the literal committed in config/dev.exs: " <>
        "#{dev.secret_key_base == committed_dev_secret()}"

    refute result.leaked?,
           "a page under the foreign origin http://#{@attacker_host}:#{port} read the " <>
             "operator's records over /live: #{inspect(result)}\n#{route}\nlog: #{log}"

    refute result.wrote?,
           "a page under the foreign origin wrote through a LiveView event: #{inspect(result)}"
  end

  test "the development socket accepts the Host guard's names and derives its LiveView salt" do
    dev = dev_endpoint_security_config()

    assert dev.check_origin == Enum.map(dev.host_guard_hosts, &("//" <> &1))
    refute dev.live_view_salt in committed_literal_salts()

    assert dev.live_view_salt ==
             RuntimeConfig.derived_salt(dev.secret_key_base, "live_view")
  end

  test "the README and llms.txt require the UI password on the run-from-source route" do
    flat = &String.replace(&1, ~r/\s+/, " ")

    section = fn path, from, to ->
      path |> File.read!() |> String.split(from) |> Enum.at(1) |> String.split(to) |> hd()
    end

    readme = flat.(section.("README.md", "### Run from source", "### API and MCP"))
    install = flat.(section.("docs/llms.txt", "## Install", "## Connect the MCP companion"))

    assert readme =~ "This route requires it"
    assert install =~ "the route requires `PORTFOLIXIR_UI_PASSWORD`"
  end

  test "control: with check_origin as the dev Host guard's allow-list the handshake is refused",
       %{dev: dev, world: world, port: port} do
    fixed = %{dev | check_origin: Enum.map(dev.host_guard_hosts, &("//" <> &1))}
    apply_endpoint_config(fixed)

    {result, log} = with_log(fn -> rebinding_attack(attacker(fixed), world, port) end)

    assert result.handshake == 403, inspect(result)
    refute result.leaked?
    refute result.wrote?
    assert log =~ "Could not check origin"
  end

  test "control: with PORTFOLIXIR_UI_PASSWORD set the forged session is refused at mount",
       %{dev: dev, world: world, port: port} do
    Application.put_env(:portfolixir, :ui_password, "synthetic-passphrase-for-the-control")
    # The origin check left open, so only the password stands between the
    # forged session and the mount.
    open = %{dev | check_origin: false}
    apply_endpoint_config(open)

    {result, _log} = with_log(fn -> rebinding_attack(attacker(open), world, port) end)

    # The handshake itself still succeeds under the foreign origin; the
    # password's fingerprint (keyed from the public secret, but over a
    # password the attacker does not know) is what stops the mount.
    assert result.handshake == 101, inspect(result)
    assert result.join_status == "error", inspect(result)
    assert result.join_redirect == "/login", inspect(result)
    refute result.leaked?
    refute result.wrote?
  end

  # -- the attack, as the rebinding page performs it ---------------------------

  defp rebinding_attack(attacker, world, port) do
    # 1. A CSRF state of the attacker's choosing and its masked token.
    {csrf_state, csrf_token} =
      Task.async(fn ->
        state = Base.url_encode64(:crypto.strong_rand_bytes(18))
        :ok = Plug.CSRFProtection.load_state(attacker.secret_key_base, state)
        {state, Plug.CSRFProtection.get_csrf_token()}
      end)
      |> Task.await()

    # 2. The `_portfolixir_key` cookie, signed with the public dev secret and
    #    the session salt derived from it by the repository's own algorithm.
    session_salt = RuntimeConfig.derived_salt(attacker.secret_key_base, "session")
    cookie_opts = COOKIE.init(signing_salt: session_salt)

    cookie =
      COOKIE.put(
        %Plug.Conn{secret_key_base: attacker.secret_key_base},
        nil,
        %{"_csrf_token" => csrf_state},
        cookie_opts
      )

    # 3. The LiveView session token, signed with the public dev secret and the
    #    literal LiveView salt; every field is a public module name.
    lv_id = "phx-rebind"

    lv_token =
      Phoenix.Token.sign(
        attacker.secret_key_base,
        attacker.live_view_salt,
        {Static.token_vsn(),
         %{
           id: lv_id,
           view: PortfolixirWeb.PortfolioAccountsLive,
           root_view: PortfolixirWeb.PortfolioAccountsLive,
           router: PortfolixirWeb.Router,
           live_session_name: :browser,
           parent_pid: nil,
           root_pid: nil,
           session: %{}
         }}
      )

    # 4. The handshake the browser sends after rebinding: the attacker's host
    #    name in Host and Origin, the cookie its own host name set.
    {:ok, sock} =
      :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false, packet: :raw], 5_000)

    key = Base.encode64(:crypto.strong_rand_bytes(16))

    request =
      "GET /live/websocket?_csrf_token=#{csrf_token}&vsn=2.0.0 HTTP/1.1\r\n" <>
        "Host: #{@attacker_host}:#{port}\r\n" <>
        "Origin: http://#{@attacker_host}:#{port}\r\n" <>
        "Upgrade: websocket\r\nConnection: Upgrade\r\n" <>
        "Sec-WebSocket-Key: #{key}\r\nSec-WebSocket-Version: 13\r\n" <>
        "Cookie: _portfolixir_key=#{cookie}\r\n\r\n"

    :ok = :gen_tcp.send(sock, request)
    {status, buffer} = read_http_status(sock, "")

    result = %{
      handshake: status,
      join_status: nil,
      join_redirect: nil,
      leaked?: false,
      leaked_excerpt: nil,
      wrote?: false,
      write_journaled_as: nil
    }

    result =
      if status == 101 do
        topic = "lv:" <> lv_id

        join =
          Jason.encode!([
            "1",
            "1",
            topic,
            "phx_join",
            %{
              "url" => "http://#{@attacker_host}:#{port}/portfolios",
              "params" => %{"_csrf_token" => csrf_token, "_mounts" => 0},
              "session" => lv_token,
              "static" => nil
            }
          ])

        :ok = :gen_tcp.send(sock, client_frame(join))
        {join_reply, buffer} = await_reply(sock, buffer, "1")
        join_text = Jason.encode!(join_reply)

        result = %{
          result
          | join_status: join_reply["status"],
            join_redirect: get_in(join_reply, ["response", "redirect", "to"]),
            leaked?:
              join_reply["status"] == "ok" and
                String.contains?(join_text, @depot_marker) and
                String.contains?(join_text, @cash_marker),
            leaked_excerpt: excerpt(join_text, @depot_marker)
        }

        result =
          if join_reply["status"] == "ok" do
            event =
              Jason.encode!([
                "1",
                "2",
                topic,
                "event",
                %{
                  "type" => "click",
                  "event" => "create_and_add_bucket",
                  "value" => %{
                    "owner" => "cash",
                    "owner_id" => to_string(world.cash.id),
                    "bucket_name" => @planted_tag
                  }
                }
              ])

            :ok = :gen_tcp.send(sock, client_frame(event))
            {_event_reply, _buffer} = await_reply(sock, buffer, "2")

            planted = Repo.get_by(Bucket, name: @planted_tag)

            journal =
              if planted do
                Repo.one(
                  from(e in Portfolixir.Journal.Entry,
                    where: e.resource_id == ^to_string(planted.id) and e.operation == :create,
                    order_by: [desc: e.id],
                    limit: 1,
                    select: {e.actor_type, e.actor_label, e.resource_type}
                  )
                )
              end

            %{
              result
              | wrote?:
                  match?(%Bucket{}, planted) and
                    planted.id in Buckets.cash_account_bucket_ids(world.cash.id),
                write_journaled_as: journal
            }
          else
            result
          end

        leave = Jason.encode!(["1", "3", topic, "phx_leave", %{}])
        :gen_tcp.send(sock, client_frame(leave))
        _ = await_reply(sock, "", "3")
        result
      else
        result
      end

    :gen_tcp.close(sock)
    await_live_views_down(PortfolixirWeb.PortfolioAccountsLive)
    result
  end

  defp excerpt(text, marker) do
    case :binary.match(text, marker) do
      {at, len} ->
        from = max(at - 60, 0)
        binary_part(text, from, min(len + 120, byte_size(text) - from))

      :nomatch ->
        nil
    end
  end

  # -- what the attacker knows: only what the repository prints ----------------

  # The secret: the literal committed in config/dev.exs, if there is one. The
  # LiveView salt: a literal committed in config/*.exs, or the repository's
  # own derivation of the public secret (runtime.exs's shape), whichever the
  # server actually uses; a salt the attacker cannot know stays unknown.
  defp attacker(server) do
    public_secret = committed_dev_secret()

    derivable =
      if public_secret,
        do: [RuntimeConfig.derived_salt(public_secret, "live_view")],
        else: []

    lv_salt =
      Enum.find(committed_literal_salts() ++ derivable, &(&1 == server.live_view_salt))

    %{
      secret_key_base: public_secret || Base.encode64(:crypto.strong_rand_bytes(48)),
      live_view_salt: lv_salt || "salt-the-attacker-cannot-know"
    }
  end

  # Whatever config/dev.exs evaluates to is in the repository, however it is
  # spelled there.
  defp committed_dev_secret do
    "config/dev.exs"
    |> then(&Path.join(@root, &1))
    |> Config.Reader.read!(env: :dev, target: :host)
    |> Keyword.fetch!(:portfolixir)
    |> Keyword.fetch!(@endpoint_mod)
    |> Keyword.get(:secret_key_base)
  end

  defp committed_literal_salts do
    for path <- ["config/config.exs", "config/dev.exs"],
        [_, salt] <-
          Regex.scan(~r/signing_salt:\s*"([^"]+)"/, File.read!(Path.join(@root, path))),
        do: salt
  end

  # -- the configuration the run-from-source route boots with ------------------

  # The values `mix phx.server` gets under MIX_ENV=dev: config/dev.exs on top
  # of config/config.exs, and config/runtime.exs evaluated under :dev.
  defp dev_endpoint_security_config do
    dev = Config.Reader.read!(Path.join(@root, "config/dev.exs"), env: :dev, target: :host)
    dev_endpoint = dev |> Keyword.fetch!(:portfolixir) |> Keyword.fetch!(@endpoint_mod)

    # config.exs ends with `import_config "#{Mix.env()}.exs"` (test.exs here),
    # which sets no :live_view; the salt below is config.exs's own literal.
    base = Config.Reader.read!(Path.join(@root, "config/config.exs"), env: :dev, target: :host)
    base_endpoint = base |> Keyword.fetch!(:portfolixir) |> Keyword.fetch!(@endpoint_mod)

    runtime =
      Config.Reader.read!(Path.join(@root, "config/runtime.exs"), env: :dev, target: :host)

    runtime_dev_touches_endpoint? =
      runtime |> Keyword.get(:portfolixir, []) |> Keyword.has_key?(@endpoint_mod)

    live_view =
      Keyword.get(dev_endpoint, :live_view) || Keyword.fetch!(base_endpoint, :live_view)

    host_guard_hosts =
      dev
      |> Keyword.fetch!(:portfolixir)
      |> Keyword.fetch!(PortfolixirWeb.HostGuard)
      |> Keyword.fetch!(:hosts)

    %{
      check_origin: Keyword.fetch!(dev_endpoint, :check_origin),
      secret_key_base: Keyword.fetch!(dev_endpoint, :secret_key_base),
      live_view_salt: Keyword.fetch!(live_view, :signing_salt),
      runtime_dev_touches_endpoint?: runtime_dev_touches_endpoint?,
      host_guard_hosts: host_guard_hosts
    }
  end

  defp apply_endpoint_config(dev) do
    :ets.insert(@endpoint_mod, {:check_origin, dev.check_origin})
    :ets.insert(@endpoint_mod, {:secret_key_base, dev.secret_key_base})
    :ets.insert(@endpoint_mod, {:live_view, [signing_salt: dev.live_view_salt]})
    Phoenix.Config.clear_cache(@endpoint_mod)
  end

  # -- a minimal WebSocket client ----------------------------------------------

  defp read_http_status(sock, acc) do
    case :binary.split(acc, "\r\n\r\n") do
      [head, rest] ->
        [status_line | _] = String.split(head, "\r\n")
        [_http, code | _] = String.split(status_line, " ")
        {String.to_integer(code), rest}

      [_incomplete] ->
        case :gen_tcp.recv(sock, 0, 5_000) do
          {:ok, data} -> read_http_status(sock, acc <> data)
          {:error, reason} -> {{:error, reason}, ""}
        end
    end
  end

  defp await_reply(sock, buffer, ref, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 10_000

    case parse_frame(buffer) do
      {:ok, 1, payload, rest} ->
        case Jason.decode!(payload) do
          [_join_ref, ^ref, _topic, "phx_reply", reply] -> {reply, rest}
          _other -> await_reply(sock, rest, ref, deadline)
        end

      {:ok, _opcode, _payload, rest} ->
        await_reply(sock, rest, ref, deadline)

      :more ->
        remaining = max(deadline - System.monotonic_time(:millisecond), 0)

        case :gen_tcp.recv(sock, 0, remaining) do
          {:ok, data} -> await_reply(sock, buffer <> data, ref, deadline)
          {:error, reason} -> {%{"status" => "transport_#{reason}"}, ""}
        end
    end
  end

  defp parse_frame(<<_fin::1, _rsv::3, op::4, 0::1, 127::7, len::64, rest::binary>>) do
    take(op, len, rest)
  end

  defp parse_frame(<<_fin::1, _rsv::3, op::4, 0::1, 126::7, len::16, rest::binary>>) do
    take(op, len, rest)
  end

  defp parse_frame(<<_fin::1, _rsv::3, op::4, 0::1, len::7, rest::binary>>) when len < 126 do
    take(op, len, rest)
  end

  defp parse_frame(_incomplete), do: :more

  defp take(op, len, rest) do
    case rest do
      <<payload::binary-size(len), tail::binary>> -> {:ok, op, payload, tail}
      _ -> :more
    end
  end

  defp client_frame(text) do
    mask = :crypto.strong_rand_bytes(4)
    len = byte_size(text)

    header =
      cond do
        len < 126 -> <<1::1, 0::3, 1::4, 1::1, len::7>>
        len < 65_536 -> <<1::1, 0::3, 1::4, 1::1, 126::7, len::16>>
        true -> <<1::1, 0::3, 1::4, 1::1, 127::7, len::64>>
      end

    masked =
      text
      |> :binary.bin_to_list()
      |> Enum.with_index()
      |> Enum.map(fn {byte, i} -> Bitwise.bxor(byte, :binary.at(mask, rem(i, 4))) end)
      |> :binary.list_to_bin()

    header <> mask <> masked
  end

  # The LiveView process runs under the endpoint, not the test: wait until it
  # is gone so nothing of it queries the sandbox after the test.
  defp await_live_views_down(view) do
    refs =
      for pid <- Process.list(),
          {:dictionary, dict} <- [Process.info(pid, :dictionary)],
          Keyword.get(dict, :"$initial_call") == {view, :mount, 3} do
        Process.monitor(pid)
      end

    for ref <- refs do
      receive do
        {:DOWN, ^ref, :process, _pid, _reason} -> :ok
      after
        5_000 -> :ok
      end
    end

    :ok
  end
end
