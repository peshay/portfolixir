defmodule PortfolixirWeb.LiveUrlParamsTest do
  @moduledoc false
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios.Snapshots
  alias PortfolixirWeb.LiveSource

  @moduletag :capture_log

  @past_bigint "99999999999999999999999"
  @past_int4 "2147483648"

  # Keys every page may be handed without reading them itself: the view scope
  # (read by a plug), the changed-since cut (read through ChangedSince) and
  # the id shapes the range guard knows.
  @shared_keys ~w(view since id security_id classification_id)

  # Every page of the live session, from the router, so a page added later is
  # swept without anyone remembering to.
  @live_pages PortfolixirWeb.Router
              |> Phoenix.Router.routes()
              |> Enum.filter(&(&1.plug == Phoenix.LiveView.Plug))
              |> Enum.map(fn route ->
                {module, _action, _opts, _extra} = route.metadata.phoenix_live_view
                {route.path, module}
              end)

  setup do
    world = base_world()
    security = create_security!()
    buy!(world, security)
    put_quote!(security, ~D[2026-01-02], "100")

    {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Tree"})

    {:ok, _snapshot} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Marker", as_of: ~D[2026-01-02]})

    %{security: security, tree: tree}
  end

  # User story (#868, E25 S4 F16):
  # As the operator following a link whose parameters were mangled,
  # I want the page to open with what it can read and drop the rest,
  # so that a bad URL never answers a server error.
  #
  # Acceptance criteria:
  # - On every live route, every parameter the page reads (and the shared
  #   id, view and since keys), set past the bigint range or past the int4
  #   range, renders or redirects — never a 500 on the static render and
  #   never a crash on the connected one; `/snapshots?snapshot=` and
  #   `/tax?year=` fall back to their default.
  # - The same holds for a non-numeric value, a list and a map in every key.
  for {path, module} <- @live_pages do
    @tag page: {path, module}
    test "#{path}: every parameter it reads survives an out-of-range or malformed value",
         %{
           conn: conn,
           page: {path, module}
         } = context do
      keys = Enum.uniq(LiveSource.param_keys(module) ++ @shared_keys)
      base = page_url(path, context)

      urls =
        for(key <- keys, value <- [@past_bigint, @past_int4], do: url(base, "#{key}=#{value}")) ++
          [
            url(base, Enum.map_join(keys, "&", &"#{&1}=not-a-number")),
            url(base, Enum.map_join(keys, "&", &"#{&1}[]=1")),
            url(base, Enum.map_join(keys, "&", &"#{&1}[a]=1"))
          ]

      crashes =
        for url <- urls, reason = visit(conn, url, 3), reason != :ok, do: {url, reason}

      assert crashes == [],
             "#{inspect(module)} crashed on:\n" <>
               Enum.map_join(crashes, "\n", fn {url, reason} -> "  #{url}: #{reason}" end)
    end
  end

  test "an out-of-range snapshot or tax year falls back to the page's default", %{conn: conn} do
    for value <- [@past_bigint, @past_int4] do
      assert {:ok, _view, html} = live(conn, "/snapshots?snapshot=#{value}")
      assert html =~ "Marker"

      assert {:ok, _view, html} = live(conn, "/tax?year=#{value}")
      assert html =~ Integer.to_string(Date.utc_today().year - 1)
    end
  end

  defp page_url("/securities/:id", %{security: security}), do: "/securities/#{security.id}"
  defp page_url("/classifications/:id", %{tree: tree}), do: "/classifications/#{tree.id}"
  defp page_url(path, _context), do: path

  defp url(base, query), do: base <> "?" <> query

  # `:ok` when the page renders or redirects (followed a few hops), else why
  # it did not: an exception on the static render, an exit on the connected
  # mount.
  defp visit(_conn, _url, 0), do: :ok

  defp visit(conn, url, hops) do
    case live(conn, url) do
      {:ok, view, _html} ->
        # The page's own async reads run on what the URL selected, too.
        _ = render_async(view, 5_000)
        :ok

      {:error, {kind, %{to: to}}} when kind in [:redirect, :live_redirect] ->
        visit(conn, to, hops - 1)
    end
  rescue
    exception -> Exception.format_banner(:error, exception)
  catch
    :exit, {{exception, _stack}, _} when is_exception(exception) ->
      Exception.format_banner(:error, exception)

    :exit, reason ->
      inspect(reason)
  end
end
