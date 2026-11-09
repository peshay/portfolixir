defmodule PortfolixirWeb.ApiV1VersionTest do
  # FR-55 (#1429), Sprint 28 V1: GET /api/v1/version, the version the
  # running instance was built from, and the proof that reading it asks
  # nothing of the network (plan D-8, carry-forward 2).
  use PortfolixirWeb.ConnCase, async: true

  alias Portfolixir.BuildVersion

  # User story:
  # As the agent the operator runs,
  # I want one small read that names the version this instance was built
  # from, its kind and the link that explains it,
  # so that I know which release I am talking to without asking the
  # operator.
  #
  # Acceptance criteria:
  # - GET /api/v1/version answers the compiled version as BuildVersion.json/1
  #   gives it: kind, value, url, tag, branch, commit, date, source and a note.
  # - It authenticates as every /api/v1 read does: no token is a 401.
  test "answers the compiled version behind the bearer token", %{conn: conn} do
    data =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")
      |> get("/api/v1/version")
      |> json_response(200)
      |> Map.fetch!("data")

    expected =
      BuildVersion.current()
      |> BuildVersion.json()
      |> Jason.encode!()
      |> Jason.decode!()

    assert data == expected
    assert data["kind"] in ["release", "build", "unknown"]

    for key <- ~w(kind value url tag branch commit date source version_note) do
      assert Map.has_key?(data, key), key
    end

    conn =
      build_conn()
      |> put_req_header("accept", "application/json")
      |> get("/api/v1/version")

    assert json_response(conn, 401)
  end

  # User story (plan D-8, carry-forward 2: a public function that performs
  # I/O is a chokepoint):
  # As the operator whose instance calls out only where B2 registered it,
  # I want the version read, its API read and its link on the screen to
  # call no HTTP client or socket, and to start no process but the one `git`
  # read B2 registers,
  # so that the link to GitHub is one I follow, and the app requests nothing.
  #
  # Acceptance criteria:
  # - No module of the version read calls Net.Http, Req, Finch, Mint, an
  #   Erlang network module or a subprocess, by its compiled calls (an alias
  #   or an import cannot hide one); Source alone calls System.cmd, which B2
  #   holds to `git` and four literal argument lists.
  # - The matcher catches a module that does (the chokepoint Net.Http, which
  #   calls Req), so the check cannot pass vacuously.
  test "the version read calls no HTTP client, socket or subprocess" do
    for module <- [BuildVersion, PortfolixirWeb.Api.V1.VersionController] do
      assert outbound_calls(module) == [], inspect(module)
    end

    assert outbound_calls(BuildVersion.Source) == [{System, :cmd, 3}]

    assert outbound_calls(Portfolixir.Net.Http) != []
  end

  @network_modules [:httpc, :inets, :gen_tcp, :gen_udp, :ssl, :socket, :hackney, :gun]
  @network_prefixes ["Elixir.Req", "Elixir.Finch", "Elixir.Mint", "Elixir.Portfolixir.Net.Http"]

  defp outbound_calls(module) do
    {:ok, {^module, [imports: imports]}} =
      module |> beam_file() |> :beam_lib.chunks([:imports])

    Enum.filter(imports, fn {target, function, _arity} ->
      name = Atom.to_string(target)

      target in @network_modules or
        Enum.any?(@network_prefixes, &(name == &1 or String.starts_with?(name, &1 <> "."))) or
        {target, function} in [
          {System, :cmd},
          {System, :shell},
          {:os, :cmd},
          {:erlang, :open_port}
        ]
    end)
  end

  # The compiled .beam on disk: under `mix test --cover` (CI's coveralls run)
  # `:code.which/1` answers `:cover_compiled`, not a path, so the file is
  # looked up in the code path by its name.
  defp beam_file(module), do: :code.where_is_file(~c"#{module}.beam")
end
