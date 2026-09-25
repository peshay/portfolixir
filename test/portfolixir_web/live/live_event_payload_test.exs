defmodule PortfolixirWeb.LiveEventPayloadTest do
  @moduledoc false
  # Synchronous: the sweep holds its sandbox connection for seconds, and the
  # test pool is small; run alone, it starves no other test of a connection.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.Repo
  alias PortfolixirWeb.LiveSource

  @moduletag :capture_log

  @past_bigint "99999999999999999999999"

  # Every page of the live session, read from the router rather than listed
  # here, so a page added later is fuzzed without anyone remembering to.
  @live_pages PortfolixirWeb.Router
              |> Phoenix.Router.routes()
              |> Enum.filter(&(&1.plug == Phoenix.LiveView.Plug))
              |> Enum.map(fn route ->
                {module, _action, _opts, _extra} = route.metadata.phoenix_live_view
                {route.path, module}
              end)

  # Each page is fuzzed over the seeded world and over an empty instance,
  # where most of its controls are not rendered at all and a pushed event
  # meets a page with none of the state the control assumes. A detail route
  # needs a record, so it runs seeded only.
  @worlds for {path, module} <- @live_pages,
              world <- [:seeded, :empty],
              world == :seeded or not String.contains?(path, ":"),
              do: {path, module, world}

  # User story (E25 S4, F17):
  # As the operator whose browser sends the page an unexpected event payload,
  # I want the page to ignore what it cannot read,
  # so that a stale tab, a mangled id or a crafted push never takes the page
  # down with it.
  #
  # Acceptance criteria:
  # - Every event every page handles, sent with a missing, malformed,
  #   out-of-range, wrongly typed or nested payload, leaves the page's
  #   process alive (a navigation away is allowed; a crash is not).
  # - An event no page knows is ignored.
  # - The same holds on an empty instance.
  for {path, module, world} <- @worlds do
    @tag page: {path, module, world}
    test "#{path} (#{world}): every event survives malformed payloads", %{
      conn: conn,
      page: {path, module, world}
    } do
      Process.flag(:trap_exit, true)

      shots =
        for {event, keys} <- [{"no-such-event", ["id"]} | LiveSource.events(module)],
            payload <- payloads(keys),
            do: {event, payload}

      assert length(shots) > 1

      {_state, crashes} =
        Enum.reduce(shots, {nil, []}, fn {event, payload}, {state, crashes} ->
          {records, view} = state || mount!(conn, path, world)

          case fire(view, event, payload) do
            {:ok, nil} -> {{records, mount_only!(conn, path, records)}, crashes}
            {:ok, view} -> {{records, view}, crashes}
            {:crash, reason} -> {nil, [{event, payload, reason} | reset_sandbox(crashes)]}
          end
        end)

      assert crashes == [],
             "#{inspect(module)} crashed on malformed payloads:\n" <>
               Enum.map_join(Enum.reverse(crashes), "\n", fn {event, payload, reason} ->
                 "  #{inspect(event)} #{inspect(payload)}: #{reason}"
               end)
    end
  end

  defp seed(:empty), do: %{}

  defp seed(:seeded) do
    world = base_world()
    security = create_security!(isin: "XS0000000001")
    buy!(world, security)
    put_quotes!(security, [{~D[2026-01-02], "100"}, {~D[2026-01-05], "101"}])

    {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Tree"})

    {:ok, _category} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: tree.id,
        name: "Branch"
      })

    {:ok, _bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Core"})
    {:ok, _view} = Buckets.create_view(Actor.owner_ui(), %{name: "Everything else"})

    %{security: security, tree: tree}
  end

  # A process that dies holding the sandbox connection takes the connection
  # with it; a fresh checkout (and a fresh world) lets the run go on and name
  # every crash rather than the first.
  defp reset_sandbox(crashes) do
    _ = Sandbox.checkin(Repo)
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
    crashes
  end

  defp mount!(conn, path, world) do
    records = seed(world)
    {records, mount_only!(conn, path, records)}
  end

  defp mount_only!(conn, path, records) do
    {:ok, view, _html} = live(conn, page_url(path, records))
    view
  end

  defp page_url("/securities/:id", %{security: security}), do: "/securities/#{security.id}"
  defp page_url("/classifications/:id", %{tree: tree}), do: "/classifications/#{tree.id}"
  defp page_url(path, _context), do: path

  # `{:ok, view}` while the page lives (`{:ok, nil}` after it navigated away,
  # so the next shot remounts), `{:crash, reason}` when its process died.
  defp fire(view, event, payload) do
    case render_hook(view, event, payload) do
      {:error, {kind, _to}} when kind in [:redirect, :live_redirect] ->
        {:ok, nil}

      _html ->
        _ = render(view)
        {:ok, view}
    end
  catch
    :exit, {{:shutdown, _navigation}, _} ->
      {:ok, nil}

    :exit, {{exception, stack}, _} ->
      {:crash, Exception.format(:error, exception, Enum.take(stack, 3))}

    :exit, reason ->
      {:crash, inspect(reason)}
  end

  # A payload a page's own markup never sends: missing keys, the wrong type
  # in every key, an id past the bigint range (as text and as a number), an
  # integer past int4, a non-finite decimal, a date far outside the ledger's
  # range, and nested maps of the same. A list payload stands for every
  # payload that is not an object at all.
  defp payloads([]), do: [%{}, %{"id" => @past_bigint}, [@past_bigint]]

  defp payloads(keys) do
    all = fn value -> Map.new(keys, &{&1, value}) end

    # Nested, an out-of-range value goes under the id-shaped keys only: an
    # amount past its column is the writers' bound (G17), not this test's.
    ids_past = Map.new(keys, &{&1, if(id_key?(&1), do: @past_bigint, else: "not-an-id")})

    [
      %{},
      [@past_bigint],
      all.("not-an-id"),
      all.(@past_bigint),
      all.(String.to_integer(@past_bigint)),
      all.("2147483648"),
      all.("-1"),
      all.("NaN"),
      all.("-9999-01-01"),
      all.(nil),
      all.([@past_bigint]),
      all.(ids_past),
      all.(all.("not-an-id")),
      all.(all.("NaN"))
    ]
  end

  defp id_key?(key),
    do: key in ~w(id view) or String.ends_with?(key, "_id") or String.ends_with?(key, "_ids")
end
