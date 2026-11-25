defmodule Portfolixir.Dashboards.Templates do
  @moduledoc """
  The curated templates (ADR-0062 §3): layouts defined in code and
  versioned with the release, never stored and never edited. „Anpassen“
  copies one into a stored dashboard (`Portfolixir.Dashboards.copy_template/3`).

  A template names only kinds that exist in its release; a template whose
  kinds are not all built is not offered. Sprint 31 ships „Überblick“
  (`"overview"`) only, its layout as planning board 01 ① draws it on the
  12-column grid; the other four of board 03 follow with their widgets.
  """

  use Gettext, backend: PortfolixirWeb.Gettext

  # Board 09's „Überblick“ on Apple's tiles (Sprint 32 E4): Sprint 31's
  # layout read on the families (S → S, M → L, T → L, L → XL, the rows
  # doubled) and arranged, as `Portfolixir.Dashboards.Grid` reads every
  # copy Sprint 31 stored.
  @overview %{
    key: "overview",
    title: "Overview",
    layout: [
      %{"kind" => "total_value", "size" => "S", "col" => 1, "row" => 1, "settings" => %{}},
      %{"kind" => "data_quality", "size" => "S", "col" => 4, "row" => 1, "settings" => %{}},
      %{"kind" => "due", "size" => "S", "col" => 7, "row" => 1, "settings" => %{}},
      %{"kind" => "off_target", "size" => "S", "col" => 10, "row" => 1, "settings" => %{}},
      %{"kind" => "performance", "size" => "XL", "col" => 1, "row" => 3, "settings" => %{}},
      %{"kind" => "allocation_drift", "size" => "L", "col" => 1, "row" => 7, "settings" => %{}},
      %{"kind" => "movers", "size" => "L", "col" => 7, "row" => 7, "settings" => %{}},
      %{"kind" => "crashes", "size" => "L", "col" => 1, "row" => 11, "settings" => %{}},
      %{"kind" => "bitcoin_cycle", "size" => "L", "col" => 7, "row" => 11, "settings" => %{}},
      %{"kind" => "sale_review", "size" => "L", "col" => 1, "row" => 15, "settings" => %{}},
      %{"kind" => "snapshots", "size" => "S", "col" => 7, "row" => 15, "settings" => %{}}
    ]
  }

  @templates [@overview]
  @by_key Map.new(@templates, &{&1.key, &1})

  @type t :: %{key: String.t(), title: String.t(), layout: [map()]}

  @doc "The templates this release offers, in the menu's order."
  @spec templates() :: [t()]
  def templates, do: @templates

  @doc "The template under `key`, matched as a string, or `:error`."
  @spec fetch(term()) :: {:ok, t()} | :error
  def fetch(key) when is_binary(key), do: Map.fetch(@by_key, key)
  def fetch(_key), do: :error

  @doc "The template's title in the current locale; `nil` for an unknown key."
  @spec title(term()) :: String.t() | nil
  def title("overview"), do: pgettext("dashboard template", "Overview")
  def title(_key), do: nil
end
