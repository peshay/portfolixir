defmodule Portfolixir.Invariants.FindingsCarryNoActionTest do
  @moduledoc """
  ADR-0049 §6: a policy finding carries **no action**.

  A finding reports that the operator's own rule, applied to a figure the
  product already shows, is on one side of the operator's own line. It does
  not say what to do: no `action`, no `recommendation`, no `suggested_*`, no
  quantity, no order-shaped field, no trade verb. The permanent non-goal "no
  advice" is the reason, and B3.5 — a digest that turns findings into
  proposed trades — stays shut. This is the sibling of
  `metrics_carry_no_verdict_test.exs` (ADR-0047 §7), built the same way: it
  walks the **rendered** payload's key set, because the payload is what a
  reviewer and an agent both read.
  """
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, buy!: 3, create_security!: 1, deposit!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Portfolios.PolicyRules

  # Matched as substrings of a key, so `suggested_quantity` or `sell_order`
  # cannot slip in under a compound name. `order` also catches `orders`;
  # `trade` catches `trades`; `quantit` catches both spellings of the plural.
  @forbidden ~w(action recommend suggest advice quantit order buy sell trade rebalanc hint)

  defp keys(value, acc \\ [])

  defp keys(%{} = map, acc) when not is_struct(map) do
    Enum.reduce(map, acc ++ Map.keys(map), fn {_key, value}, inner -> keys(value, inner) end)
  end

  defp keys(list, acc) when is_list(list),
    do: Enum.reduce(list, acc, fn value, inner -> keys(value, inner) end)

  defp keys(_value, acc), do: acc

  defp offenders(data) do
    data
    |> keys()
    |> Enum.filter(fn key ->
      downcased = String.downcase(to_string(key))
      Enum.any?(@forbidden, &String.contains?(downcased, &1))
    end)
    |> Enum.uniq()
  end

  defp rule!(portfolio, name, version) do
    {:ok, _rule} =
      PolicyRules.create_rule(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: name,
        version: version
      })
  end

  # User story (ADR-0049 §6, the "no advice" non-goal):
  # As the maintainer holding the line between a finding and a trade,
  # I want the findings payload's key set checked by the build,
  # so that an action cannot be added to a finding by anyone who did not read
  # the record.
  #
  # Acceptance criteria:
  # - No key of the rendered findings payload contains action, recommend,
  #   suggest, advice, quantity, order, buy, sell, trade, rebalance or hint.
  # - The walk covers a payload with every state — breached, ok and
  #   undetermined — so no state can carry a key another hides.
  test "the findings payload carries no action key", %{conn: conn} do
    today = Portfolixir.Clock.today()
    world = base_world()
    security = create_security!(name: "Action Co", ticker: "ACT")
    deposit!(world, "1000", Date.add(today, -3))
    buy!(world, security, quantity: "5", price: "100", date: Date.add(today, -3))
    put_quote!(security, Date.add(today, -3), "100")

    rule!(world.portfolio, "Breached", %{
      subject_type: "security",
      security_id: security.id,
      measure: "weight",
      kind: "cap",
      threshold: "10",
      severity: "hard"
    })

    rule!(world.portfolio, "Ok", %{
      subject_type: "cash",
      measure: "weight",
      kind: "cap",
      threshold: "90",
      severity: "warn"
    })

    rule!(world.portfolio, "Undetermined", %{
      subject_type: "basis",
      measure: "volatility",
      window: "90d",
      kind: "cap",
      threshold: "15",
      severity: "warn"
    })

    %{"data" => data} =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")
      |> get("/api/v1/portfolios/#{world.portfolio.id}/policy_findings")
      |> json_response(200)

    assert Enum.sort(Enum.map(data["findings"], & &1["state"])) ==
             ["breached", "ok", "undetermined"]

    assert offenders(data) == [],
           "ADR-0049 §6: the findings payload carries action-shaped keys " <>
             "#{inspect(offenders(data))}. A finding is the operator's rule applied to a " <>
             "figure; turning it into a trade is B3.5 and stays shut."
  end
end
