defmodule Portfolixir.SettingsTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Settings

  # User story:
  # As a local portfolio maintainer,
  # I want a minimal server-side preference store,
  # so that my default view and dismissed notices survive across sessions and
  # browsers (client-only storage cannot feed the LiveView mount).
  #
  # Acceptance criteria:
  # - A preference is a keyed string value; reading an unset key returns nil.
  # - Writing an existing key overwrites it (single row per key).
  # - Deleting a key returns the read to nil.
  test "stores, overwrites and deletes keyed preferences" do
    assert Settings.get("greeting") == nil

    :ok = Settings.put("greeting", "hello")
    assert Settings.get("greeting") == "hello"

    :ok = Settings.put("greeting", "servus")
    assert Settings.get("greeting") == "servus"

    :ok = Settings.delete("greeting")
    assert Settings.get("greeting") == nil
  end

  # User story:
  # As a local portfolio maintainer,
  # I want to mark one view as my default,
  # so that the Wealth page and dashboard open on the slice of wealth I steer.
  #
  # Acceptance criteria:
  # - With no preference set the default is nil (the built-in "Everything").
  # - Setting a view id persists it; setting nil clears back to Everything.
  # - A default that no longer names a live view reads as nil (graceful).
  test "default view preference round-trips and degrades gracefully" do
    assert Settings.default_view_id() == nil

    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Mine"})
    :ok = Settings.set_default_view(view.id)
    assert Settings.default_view_id() == view.id

    :ok = Settings.set_default_view(nil)
    assert Settings.default_view_id() == nil

    :ok = Settings.set_default_view(view.id)
    {:ok, _} = Buckets.delete_view(Actor.owner_ui(), view)
    assert Settings.default_view_id() == nil
  end

  # User story:
  # As a local portfolio maintainer whose portfolios were migrated to views,
  # I want the one-time migration notice to stay dismissed once I close it,
  # so that my daily check-in is not nagged by a notice I already read.
  #
  # Acceptance criteria:
  # - The notice starts undismissed; dismissing persists server-side.
  test "migration notice dismissal persists" do
    refute Settings.migration_notice_dismissed?()
    :ok = Settings.dismiss_migration_notice()
    assert Settings.migration_notice_dismissed?()
  end
end
