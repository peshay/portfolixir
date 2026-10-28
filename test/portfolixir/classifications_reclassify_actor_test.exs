defmodule Portfolixir.ClassificationsReclassifyActorTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Journal

  defp etf_category do
    Classifications.ensure_builtins()

    Classifications.list_trees()
    |> Enum.find(&(&1.classification.key == "asset_class"))
    |> Map.fetch!(:categories)
    |> Enum.find(&(&1.key == "etf"))
  end

  defp security! do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{name: "Synthetic Reclass", currency_code: "EUR"})

    security
  end

  defp asset_class_entries(actor_type) do
    Journal.list_entries(resource_type: "security", actor_type: actor_type)
    |> Enum.filter(&Map.has_key?(&1.after, "security_ids"))
  end

  # User story (security review 2026-10-12, H62):
  # As the operator reading the audit journal,
  # I want a move in the asset-class tree, and its reset to automatic,
  # journaled under the actor the caller names,
  # so that a future API or agent path to these writers is attributed to its
  # credential instead of to the operator.
  #
  # Acceptance criteria:
  # - reclassify_securities and reset_asset_class take an Actor first and
  #   journal their aggregate security entry under it.
  test "a reclassification and its reset journal the actor they are given" do
    security = security!()
    agent = Actor.api_token_rw("synthetic")

    assert {:ok, 1} =
             Classifications.reclassify_securities(agent, [security.id], etf_category().id)

    assert Catalog.get_security(security.id).asset_class == "etf"

    assert {:ok, 1} = Classifications.reset_asset_class(agent, [security.id])
    assert Catalog.get_security(security.id).asset_class == nil

    entries = asset_class_entries(:api_token_rw)
    assert length(entries) == 2
    assert Enum.all?(entries, &(&1.actor_label == "synthetic"))
    assert asset_class_entries(:owner_ui) == []
  end
end
