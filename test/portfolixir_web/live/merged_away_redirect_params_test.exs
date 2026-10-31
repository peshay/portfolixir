defmodule PortfolixirWeb.MergedAwayRedirectParamsTest do
  use PortfolixirWeb.ConnCase

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Lifecycle
  alias Portfolixir.WorldFixtures

  setup do
    # The same name, so the merge resolves the source's stored identity.
    # Both are EUR / etf (fixture defaults), so the cur[]=EUR and
    # class[]=etf chips list them both.
    source = WorldFixtures.create_security!(name: "Synthetic Merge Fund", ticker: nil)
    target = WorldFixtures.create_security!(name: "Synthetic Merge Fund", ticker: nil)
    %{source: source, target: target}
  end

  # User story (security review 2026-10-12, H16):
  # As the operator following a link to a security a merge took away,
  # I want to land on the survivor whatever list or filter parameters the
  # link carries,
  # so that a bookmark of my filtered list or a stale row never ends on an
  # error page (ADR-0050 §12).
  #
  # Acceptance criteria:
  # - A link with scalar parameters lands on the survivor and keeps them.
  # - A link with list parameters (the list page's own chips) lands on the
  #   survivor and carries them as `key[]` pairs; a map-shaped parameter is
  #   dropped, never a 500.
  # - A stale row clicked, or "Release…" pressed, after the merge opens the
  #   survivor with its merged notice, chips active or not.
  test "control: a scalar-only link to a merged-away security lands on the survivor", ctx do
    merge!(ctx.source, ctx.target)

    assert {:error, {:live_redirect, %{to: to}}} =
             live(ctx.conn, "/securities/#{ctx.source.id}?tab=chart")

    assert to == "/securities/#{ctx.target.id}?merged_from=#{ctx.source.id}&tab=chart"
  end

  test "control: the HTTP answer to a scalar-only link is a 302 to the survivor", ctx do
    merge!(ctx.source, ctx.target)
    conn = get(ctx.conn, "/securities/#{ctx.source.id}?tab=chart")

    assert conn.status == 302

    assert get_resp_header(conn, "location") == [
             "/securities/#{ctx.target.id}?merged_from=#{ctx.source.id}&tab=chart"
           ]
  end

  test "control: a stale row merged away meanwhile opens the survivor without a chip", ctx do
    {:ok, view, _html} = live(ctx.conn, "/securities")
    assert has_element?(view, "#security-row-#{ctx.source.id}")

    merge!(ctx.source, ctx.target, Actor.api_token_rw("synthetic"))

    outcome =
      interact(fn ->
        view |> element("#security-row-#{ctx.source.id}") |> render_click()
      end)

    assert outcome == :alive
    assert has_element?(view, "#security-row-#{ctx.target.id}.is-selected")
    assert has_element?(view, "#security-detail-pane [data-role='merged-notice']")
  end

  test "a bookmark of the filtered list (chip URL) lands on the survivor", ctx do
    merge!(ctx.source, ctx.target)

    path =
      "/securities/#{ctx.source.id}?cur[]=EUR&class[]=etf&filter[]=name:contains:Synthetic&tab=chart"

    result = attempt(fn -> live(ctx.conn, path) end)

    assert {:error, {:live_redirect, %{to: to}}} = result
    assert String.starts_with?(to, "/securities/#{ctx.target.id}?")
    assert {"merged_from", "#{ctx.source.id}"} in query_pairs(to)
    assert {"tab", "chart"} in query_pairs(to)
    assert {"cur[]", "EUR"} in query_pairs(to)
    assert {"class[]", "etf"} in query_pairs(to)
    assert {"filter[]", "name:contains:Synthetic"} in query_pairs(to)
  end

  test "the HTTP answer to that bookmark is a redirect to the survivor, not the 500 page", ctx do
    merge!(ctx.source, ctx.target)
    path = "/securities/#{ctx.source.id}?cur[]=EUR"

    {answer, _log} =
      with_log(fn ->
        try do
          conn = get(ctx.conn, path)
          {conn.status, get_resp_header(conn, "location")}
        rescue
          exception ->
            {status, _headers, body} =
              assert_error_sent(:internal_server_error, fn -> get(build_conn(), path) end)

            {:raised, unwrap(exception).__struct__, status, String.slice(body, 0, 60)}
        end
      end)

    assert {302, ["/securities/" <> to]} = answer
    assert String.starts_with?(to, "#{ctx.target.id}?")
  end

  test "a map-shaped parameter does not stop the redirect either", ctx do
    merge!(ctx.source, ctx.target)

    result = attempt(fn -> live(ctx.conn, "/securities/#{ctx.source.id}?f[a]=1") end)

    assert {:error, {:live_redirect, %{to: to}}} = result
    assert String.starts_with?(to, "/securities/#{ctx.target.id}?")
    assert query_pairs(to) == [{"merged_from", "#{ctx.source.id}"}]
  end

  # The list does not reload on a merge made elsewhere, so a row merged
  # away meanwhile stays clickable.
  test "a stale row the agent merged away meanwhile opens the survivor (chip active)", ctx do
    {:ok, view, _html} = live(ctx.conn, "/securities?cur[]=EUR")
    assert has_element?(view, "#security-row-#{ctx.source.id}")

    merge!(ctx.source, ctx.target, Actor.api_token_rw("synthetic"))

    outcome =
      interact(fn ->
        view |> element("#security-row-#{ctx.source.id}") |> render_click()
      end)

    assert outcome == :alive
    assert has_element?(view, "#security-row-#{ctx.target.id}.is-selected")
    assert has_element?(view, "#security-detail-pane [data-role='merged-notice']")
  end

  # Pinned in securities_quote_release_live_test.exs without a chip, here
  # with one.
  test "Release… on a security merged away meanwhile follows the merge with a chip active",
       ctx do
    WorldFixtures.put_quote!(ctx.source, Date.add(Portfolixir.Clock.today(), -3), "100")
    {:ok, view, _html} = live(ctx.conn, "/securities/#{ctx.source.id}?tab=quotes&cur[]=EUR")
    assert has_element?(view, "[data-role='release-manual-quotes']")

    merge!(ctx.source, ctx.target, Actor.api_token_rw("synthetic"))

    outcome =
      interact(fn ->
        view |> element("[data-role='release-manual-quotes']") |> render_click()
      end)

    assert outcome == :alive
    refute has_element?(view, "#quote-release-dialog")
    assert has_element?(view, "#security-row-#{ctx.target.id}.is-selected")
    assert has_element?(view, "#security-detail-pane [data-role='merged-notice']")
  end

  defp merge!(source, target, actor \\ Actor.owner_ui()) do
    {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)

    {:ok, _record, :applied} =
      Lifecycle.merge_security(actor, source.id, target.id, %{
        plan_digest: preview.plan_digest,
        collapse_key_equal: false
      })
  end

  # A static render: its result, or the exception it raised.
  defp attempt(fun) do
    {result, _log} =
      with_log(fn ->
        try do
          fun.()
        rescue
          exception ->
            exception = unwrap(exception)
            {:raised, exception.__struct__, String.slice(Exception.message(exception), 0, 90)}
        end
      end)

    result
  end

  # A connected interaction: :alive when the page's process survives it,
  # else the exception the page's process died of. The wait for the EXIT
  # keeps the crash report inside the capture.
  defp interact(fun) do
    Process.flag(:trap_exit, true)

    {result, _log} =
      with_log(fn ->
        try do
          fun.()
          :alive
        catch
          :exit, {{%{__exception__: true} = exception, _stack}, _call} ->
            await_exit()

            {:page_died, exception.__struct__, String.slice(Exception.message(exception), 0, 90)}

          :exit, reason ->
            await_exit()
            {:page_died, reason}
        end
      end)

    result
  end

  defp await_exit do
    receive do
      {:EXIT, _pid, _reason} -> Process.sleep(100)
    after
      1_000 -> :ok
    end
  end

  defp unwrap(%Plug.Conn.WrapperError{reason: reason}), do: unwrap(reason)
  defp unwrap(exception), do: exception

  defp query_pairs(to),
    do: to |> URI.parse() |> Map.fetch!(:query) |> URI.query_decoder() |> Enum.to_list()
end
