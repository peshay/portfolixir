defmodule Portfolixir.SettingsTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Settings

  # User story (#1272):
  # As the maintainer of the audit journal,
  # I want the raw keyed writers of the preference store to be private,
  # so that no caller can set or clear the default view around
  # `set_default_view/2`, the path that journals it under its setter's actor.
  #
  # Acceptance criteria:
  # - `Settings.put/2` and `Settings.delete/1` are not public.
  # - Each instance-state key is still written, overwritten and cleared
  #   through its own helper, and reads back through `get/1`.
  test "the raw keyed writers are private, the per-key helpers still write" do
    Code.ensure_loaded!(Settings)
    refute function_exported?(Settings, :put, 2)
    refute function_exported?(Settings, :delete, 1)

    assert Settings.get("portfolio_migration_notice_dismissed") == nil

    :ok = Settings.dismiss_migration_notice()
    :ok = Settings.dismiss_migration_notice()
    assert Settings.get("portfolio_migration_notice_dismissed") == "true"

    :ok = Settings.reset_migration_notice()
    assert Settings.get("portfolio_migration_notice_dismissed") == nil
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

    {:ok, view} =
      Buckets.create_view(Actor.owner_ui(), %{name: "Mine #{System.unique_integer([:positive])}"})

    :ok = Settings.set_default_view(Portfolixir.Actor.owner_ui(), view.id)
    assert Settings.default_view_id() == view.id

    :ok = Settings.set_default_view(Portfolixir.Actor.owner_ui(), nil)
    assert Settings.default_view_id() == nil

    :ok = Settings.set_default_view(Portfolixir.Actor.owner_ui(), view.id)
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
