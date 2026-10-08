defmodule Portfolixir.Settings do
  @moduledoc """
  Minimal keyed preference store (ADR-0024 user-facing consequences).

  A preference is one row per key with a plain string value — deliberately the
  smallest server-side mechanism that lets the LiveView mount read the
  user-settable **default view** and dismissed one-time notices (client-only
  storage cannot feed a mount). UI preferences are not financial records, so
  writes are not audit-journaled (ADR-0017 arms bookkeeping tables only).

  Domain helpers wrap the raw store so callers never parse strings themselves:

    * `default_view_id/0` / `set_default_view/1` — the view the Wealth page and
      dashboard open on; `nil` means the built-in "Everything" scope.
    * `migration_notice_dismissed?/0` / `dismiss_migration_notice/0` — the
      one-time "your portfolios are now views" notice (ADR-0024 migration).
    * `fx_history_sought/0` / `add_fx_history_sought/1` — the currencies a
      completed automatic backfill of the historical exchange rates already
      sought (#1120, D-5 of the Sprint 20 plan). Not a preference but one
      piece of instance state that must survive a restart; this is the
      smallest keyed store the instance has, so it lives here
      (`Portfolixir.Fx.HistoryGaps` reads it).
  """

  import Ecto.Query

  alias Portfolixir.Buckets
  alias Portfolixir.Repo
  alias Portfolixir.Settings.Setting

  @default_view_key "default_view_id"
  @migration_notice_key "portfolio_migration_notice_dismissed"
  @fx_history_sought_key "fx_history_backfill_sought"

  @doc "Reads the preference under `key`; `nil` when unset."
  @spec get(String.t()) :: String.t() | nil
  def get(key) when is_binary(key) do
    Repo.one(from(s in Setting, where: s.key == ^key, select: s.value))
  end

  @doc "Upserts the preference under `key` (one row per key)."
  @spec put(String.t(), String.t()) :: :ok
  def put(key, value) when is_binary(key) and is_binary(value) do
    %Setting{}
    |> Setting.changeset(%{key: key, value: value})
    |> Repo.insert!(
      on_conflict: {:replace, [:value, :updated_at]},
      conflict_target: :key
    )

    :ok
  end

  @doc "Deletes the preference under `key`; a missing key is a no-op."
  @spec delete(String.t()) :: :ok
  def delete(key) when is_binary(key) do
    Repo.delete_all(from(s in Setting, where: s.key == ^key))
    :ok
  end

  @doc """
  The user's default view id, or `nil` for the built-in "Everything" scope.

  A stored id that no longer names a live view reads as `nil`, so deleting a
  view degrades the default gracefully instead of pinning a ghost scope.
  """
  @spec default_view_id() :: integer() | nil
  def default_view_id do
    with raw when is_binary(raw) <- get(@default_view_key),
         {id, ""} when id > 0 <- Integer.parse(raw),
         %{} <- Buckets.get_view(id) do
      id
    else
      _ -> nil
    end
  end

  @doc "Persists `view_id` as the default view; `nil` clears back to Everything."
  @spec set_default_view(integer() | nil) :: :ok
  def set_default_view(nil), do: delete(@default_view_key)

  def set_default_view(view_id) when is_integer(view_id) and view_id > 0 do
    put(@default_view_key, Integer.to_string(view_id))
  end

  @doc "Whether the one-time portfolio-migration notice was dismissed."
  @spec migration_notice_dismissed?() :: boolean()
  def migration_notice_dismissed?, do: get(@migration_notice_key) == "true"

  @doc "Dismisses the one-time portfolio-migration notice permanently."
  @spec dismiss_migration_notice() :: :ok
  def dismiss_migration_notice, do: put(@migration_notice_key, "true")

  @doc """
  Forgets a dismissal of the portfolio-migration notice (fix round): called by
  the seed rollback, so a later re-seed is announced again instead of staying
  silently suppressed by a stale dismissal.
  """
  @spec reset_migration_notice() :: :ok
  def reset_migration_notice, do: delete(@migration_notice_key)

  @doc """
  The currencies a completed automatic backfill of the historical exchange
  rates already sought (#1120), sorted; `[]` before the first one. Stored as
  one comma-separated value of currency codes.
  """
  @spec fx_history_sought() :: [String.t()]
  def fx_history_sought do
    case get(@fx_history_sought_key) do
      nil -> []
      value -> value |> String.split(",", trim: true) |> Enum.sort()
    end
  end

  @doc """
  Adds `currencies` to `fx_history_sought/0`: cumulative, and a code already
  there is not added twice.
  """
  @spec add_fx_history_sought([String.t()]) :: :ok
  def add_fx_history_sought([]), do: :ok

  def add_fx_history_sought(currencies) when is_list(currencies) do
    sought = currencies |> Enum.concat(fx_history_sought()) |> Enum.uniq() |> Enum.sort()
    put(@fx_history_sought_key, Enum.join(sought, ","))
  end
end
