defmodule PortfolixirWeb.LiveComponentPayloadTest do
  @moduledoc false
  # Synchronous: the sweep holds its sandbox connection for seconds, and the
  # test pool is small; run alone, it starves no other test of a connection.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Portfolios.PolicyRules
  alias PortfolixirWeb.LiveSource

  @moduletag :capture_log

  @past_bigint "99999999999999999999999"

  # Every LiveComponent of the application, from the compiled modules, so a
  # component added later fails the coverage assertion below until it has an
  # opener here. A component's events reach it directly, past the page's
  # event hooks, so each one must read its own payloads.
  @components (
                {:ok, modules} = :application.get_key(:portfolixir, :modules)

                modules
                |> Enum.filter(fn module ->
                  Code.ensure_loaded?(module) and function_exported?(module, :__live__, 0) and
                    module.__live__()[:kind] == :component
                end)
                |> Enum.sort()
              )

  # How each component is opened: the page, the event that renders it (with
  # the payload that event needs from the seeded records), and its DOM id.
  defp openers(%{security: security, rule: rule, cash: cash, depot: depot}) do
    %{
      PortfolixirWeb.Risk.PolicyRuleDialog => [
        {"/risk", "new_rule", %{}, "#policy-rule-dialog"},
        {"/risk", "edit_rule", %{"id" => rule.id}, "#policy-rule-dialog"}
      ],
      PortfolixirWeb.Securities.SecurityFormDialog => [
        {"/securities", "open_new", %{}, "#security-form-dialog"},
        {"/securities", "row_action", %{"action" => "edit", "id" => security.id},
         "#security-form-dialog"}
      ],
      PortfolixirWeb.Securities.SplitWizardDialog => [
        {"/securities/#{security.id}", "open_split_wizard", %{}, "#split-wizard-dialog"}
      ],
      PortfolixirWeb.Securities.FilterPopover => [
        {"/securities", "toggle_popover", %{"popover" => "filter"}, "#filter-popover"}
      ],
      PortfolixirWeb.PortfolioAccounts.AccountFormDialog => [
        {"/portfolios", "open_account_dialog", %{}, "#account-form-dialog"}
      ],
      # ADR-0050 (L5a): the rename and the two-step merge of Accounts & depots.
      PortfolixirWeb.PortfolioAccounts.RenameDialog => [
        {"/portfolios", "row_rename", %{"kind" => "cash", "id" => cash.id}, "#rename-dialog"},
        {"/portfolios", "row_rename", %{"kind" => "depot", "id" => depot.id}, "#rename-dialog"}
      ],
      PortfolixirWeb.PortfolioAccounts.MergeDialog => [
        {"/portfolios", "row_merge", %{"kind" => "cash", "id" => cash.id}, "#merge-dialog"},
        {"/portfolios", "row_merge", %{"kind" => "depot", "id" => depot.id}, "#merge-dialog"}
      ],
      # ADR-0050 §9 (L5b): the security merge of the securities page.
      PortfolixirWeb.Securities.MergeDialog => [
        {"/securities", "row_action", %{"action" => "merge", "id" => security.id},
         "#security-merge-dialog"}
      ]
    }
  end

  setup do
    world = base_world()
    security = create_security!(isin: "XS0000000002")
    buy!(world, security)
    put_quote!(security, ~D[2026-01-02], "100")

    {:ok, rule} =
      PolicyRules.create_rule(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        name: "Cap",
        version: %{
          subject_type: "security",
          security_id: security.id,
          measure: "weight",
          kind: "cap",
          threshold: "10",
          severity: "hard"
        }
      })

    %{records: %{security: security, rule: rule, cash: world.cash, depot: world.depot}}
  end

  test "every LiveComponent has an opener here" do
    assert length(@components) >= 5
    stub = %{id: 1}

    assert Enum.sort(Map.keys(openers(%{security: stub, rule: stub, cash: stub, depot: stub}))) ==
             @components
  end

  # User story (E25 S4, F17):
  # As the operator with a dialog open,
  # I want an event the dialog cannot read to change nothing,
  # so that a stale tab or a crafted push never takes the page down with it.
  #
  # Acceptance criteria:
  # - Every event every LiveComponent handles, sent to the open component
  #   with a missing, malformed, out-of-range, wrongly typed or nested
  #   payload, leaves the page alive.
  # - An event the component does not know is ignored.
  # - The policy-rule dialog's retire and delete act only on a loaded rule:
  #   pushed to the new-rule dialog they change nothing.
  for module <- @components do
    @tag component: module
    test "#{inspect(module)}: every event survives malformed payloads", %{
      conn: conn,
      component: module,
      records: records
    } do
      Process.flag(:trap_exit, true)

      events = [{"no-such-event", ["id"]} | LiveSource.events(module)]
      assert length(events) > 1

      crashes =
        for opener <- Map.fetch!(openers(records), module), reduce: [] do
          acc ->
            shots = for {event, keys} <- events, payload <- payloads(keys), do: {event, payload}

            # A crash can take the sandbox connection with it, so the first
            # one ends this opener's run.
            {_view, acc} =
              Enum.reduce_while(shots, {nil, acc}, fn {event, payload}, {view, acc} ->
                view = view || open!(conn, opener)

                case fire(view, opener, event, payload) do
                  {:ok, view} ->
                    {:cont, {view, acc}}

                  {:crash, reason} ->
                    {:halt, {nil, [{elem(opener, 1), event, payload, reason} | acc]}}
                end
              end)

            acc
        end
        |> Enum.reverse()

      assert crashes == [],
             "#{inspect(module)} crashed on malformed payloads:\n" <>
               Enum.map_join(crashes, "\n", fn {opened_by, event, payload, reason} ->
                 "  (#{opened_by}) #{inspect(event)} #{inspect(payload)}: #{reason}"
               end)
    end
  end

  test "retire and delete pushed to the new-rule dialog change nothing", %{
    conn: conn,
    records: %{rule: rule}
  } do
    {:ok, view, _html} = live(conn, "/risk")
    render_hook(view, "new_rule", %{})

    for event <- ["retire", "delete"] do
      view |> with_target("#policy-rule-dialog") |> render_hook(event, %{})
      assert Process.alive?(view.pid)
    end

    assert %{status: :in_force} = PolicyRules.get_rule(rule.id)
  end

  defp open!(conn, {path, open_event, open_payload, _target}) do
    {:ok, view, _html} = live(conn, path)
    render_hook(view, open_event, open_payload)
    view
  end

  # `{:ok, view}` while the component is still open (`{:ok, nil}` once it
  # closed or the page navigated, so the next shot reopens it), or why the
  # page died.
  defp fire(view, {_path, _event, _payload, target}, event, payload) do
    view |> with_target(target) |> render_hook(event, payload)
    _ = render(view)

    if has_element?(view, target), do: {:ok, view}, else: {:ok, nil}
  catch
    :exit, {{:shutdown, _navigation}, _} -> {:ok, nil}
    :exit, {{exception, _stack}, _} -> {:crash, Exception.format_banner(:error, exception)}
    :exit, reason -> {:crash, inspect(reason)}
  end

  defp payloads([]), do: [%{}, [@past_bigint]]

  defp payloads(keys) do
    all = fn value -> Map.new(keys, &{&1, value}) end

    [
      %{},
      [@past_bigint],
      all.("not-an-id"),
      all.(@past_bigint),
      all.("NaN"),
      all.("-9999-01-01"),
      all.(nil),
      all.([@past_bigint]),
      all.(all.("not-an-id"))
    ]
  end
end
