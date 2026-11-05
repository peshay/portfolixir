defmodule PortfolixirWeb.Journal.RowTest do
  # The audit journal's row in words (Sprint 23 V3, board
  # ux-design-2026-11-02-sprint23/03-journal), read off entries as the API
  # answers them. The page's tests write real history; these pin the
  # shapes a page of real history rarely holds. Every value is synthetic.
  use ExUnit.Case, async: true

  alias Portfolixir.Journal.Entry
  alias PortfolixirWeb.Journal.Row

  defp entry(attrs) do
    struct!(
      Entry,
      Map.merge(
        %{
          id: 1,
          actor_type: :owner_ui,
          actor_label: nil,
          operation: :create,
          resource_type: "policy_rule",
          resource_id: "9",
          before: nil,
          after: nil,
          inserted_at: ~U[2026-11-02 18:00:23.000000Z]
        },
        attrs
      )
    )
  end

  # User story (Sprint 23 V3):
  # As the operator reading the audit journal,
  # I want each entry named and linked by what it holds,
  # so that I see which record changed and where to read it.
  #
  # Acceptance criteria:
  # - A merge names what it merged: cash accounts, depots, securities; a
  #   kind no label knows names nothing beyond its kind and id.
  # - A booking without a readable date reads its kind alone.
  # - An entry with no after-image reads its name from its before-image;
  #   one with neither reads its kind and id.
  # - A security's quotes link the security, a target weight or plan the
  #   allocation tab, a rule and its versions the Risk page.
  test "each kind is named and linked by what it holds" do
    names =
      for kind <- ["cash_account", "securities_account", "security", "unknown"] do
        Row.build(
          entry(%{resource_type: "merge_record", resource_id: "5", after: %{"kind" => kind}})
        ).entity
      end

    assert names == [
             "Merge 5 · Cash accounts",
             "Merge 5 · Depots",
             "Merge 5 · Securities",
             "Merge 5"
           ]

    booking =
      entry(%{
        resource_type: "transaction",
        resource_id: "7",
        after: %{"type" => "deposit", "date" => "not a date"}
      })

    assert Row.build(booking).entity == "Transaction 7 · Deposit"

    before_only =
      entry(%{operation: :update, before: %{"name" => "Cash ceiling"}, after: nil})

    assert Row.build(before_only).entity == "Rule 9 · Cash ceiling"
    assert Row.build(entry(%{})).entity == "Rule 9"

    assert Row.build(entry(%{resource_type: "security_quotes", resource_id: "12"})).href ==
             "/securities/12"

    assert Row.build(entry(%{resource_type: "target"})).href == "/portfolio?tab=allocation"
    assert Row.build(entry(%{resource_type: "target_plan"})).href == "/portfolio?tab=allocation"
    assert Row.build(entry(%{})).href == "/risk"
    assert Row.build(entry(%{resource_type: "policy_rule_version"})).href == "/risk"
  end

  # Acceptance criteria (Sprint 23 V3, the fold):
  # - A delete whose before-image was not stored folds no values.
  test "a delete without a before-image folds no values" do
    assert Row.build(entry(%{operation: :delete})).change == %{lines: [:deleted], values: []}
  end

  # User story (ADR-0055; Sprint 25 plan, F1):
  # As the operator reading the audit journal,
  # I want a recorded prediction named as one, in my language,
  # so that the agent's calls read as calls, not as a code.
  #
  # Acceptance criteria:
  # - A prediction's create reads "Prediction <id>", in German "Prognose <id>".
  test "a prediction is named as its kind and id" do
    prediction = entry(%{resource_type: "prediction", resource_id: "7", after: %{}})

    assert Row.build(prediction).entity == "Prediction 7"

    Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn ->
      assert Row.build(prediction).entity == "Prognose 7"
    end)
  end

  # User story (the Sprint 25 closing act's correctness lens):
  # As the operator filtering the audit journal by kind,
  # I want the kind select to offer predictions,
  # so that the agent's recorded calls can be listed on their own.
  #
  # Acceptance criteria:
  # - Row.kinds/0, the kind select's list, includes "prediction", right
  #   after the research note, and every kind it offers has a label.
  test "the kind select offers predictions" do
    assert "prediction" in Row.kinds()

    assert Enum.drop_while(Row.kinds(), &(&1 != "security_note")) |> Enum.take(2) ==
             ["security_note", "prediction"]

    for kind <- Row.kinds() do
      refute Row.kind_label(kind) == kind, kind
    end
  end
end
