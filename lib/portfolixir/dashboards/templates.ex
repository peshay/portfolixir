defmodule Portfolixir.Dashboards.Templates do
  @moduledoc """
  The curated templates (ADR-0062 §3): layouts defined in code and
  versioned with the release, never stored and never edited. „Anpassen“
  copies one into a stored dashboard (`Portfolixir.Dashboards.copy_template/3`);
  the gallery offers each (Sprint 32 S4), the starters and the themes
  „Krypto Lover“ and „Rücksetzer“ (S5).

  A template names only kinds that exist in its release; a template whose
  kinds are not all built is not offered. A template marked `starter` is
  stored once, on the first start of the release that brings it
  (`Portfolixir.Dashboards.Starters`; ADR-0062's amendment of 2026-11-25,
  point 5); from then on the copy is the operator's. Sprint 31 ships „Überblick“
  (`"overview"`) only, its layout as planning board 01 ① draws it on the
  12-column grid; the other four of board 03 follow with their widgets.
  """

  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Dashboards.Widgets

  # Board 09's „Überblick“ on Apple's tiles (Sprint 32 E4): Sprint 31's
  # layout read on the families (S → S, M → L, T → L, L → XL, the rows
  # doubled) and arranged, as `Portfolixir.Dashboards.Grid` reads every
  # copy Sprint 31 stored.
  @overview %{
    key: "overview",
    title: "Overview",
    # Sprint 32 S3: stored once on the first start of this release
    # (`Portfolixir.Dashboards.Starters`).
    starter: true,
    asks_scope: false,
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

  # --- S32 W2 begin ---
  # „Allokation & Ziele“ (I57; board 02 ②; Sprint 32 W2): Wealth's tab as
  # a starter, its two sections as section widgets in the size „Zeile“, in
  # the tab's order — the summary line, then the allocation.
  @allocation_targets %{
    key: "allocation_targets",
    title: "Allocation & targets",
    starter: true,
    asks_scope: false,
    layout: [
      %{"kind" => "summary_line", "size" => "row", "col" => 1, "row" => 1, "settings" => %{}},
      %{"kind" => "allocation", "size" => "row", "col" => 1, "row" => 2, "settings" => %{}}
    ]
  }

  # --- S32 W2 end ---

  # --- S32 W3 begin ---
  # „Snapshots“ (I57; board 02 ②; Sprint 32 W3): Wealth's tab as a starter,
  # the comparison over the list, as the tab draws them.
  @snapshots %{
    key: "snapshots",
    title: "Snapshots",
    starter: true,
    asks_scope: false,
    layout: [
      %{
        "kind" => "snapshot_comparison",
        "size" => "row",
        "col" => 1,
        "row" => 1,
        "settings" => %{}
      },
      %{"kind" => "snapshot_list", "size" => "row", "col" => 1, "row" => 2, "settings" => %{}}
    ]
  }

  # --- S32 W3 end ---

  # --- S32 W4 begin ---
  # „Risiko“ (I57; board 02 ②; Sprint 32 W4): Wealth's tab as a starter,
  # its six sections in the tab's order, each in the size „Zeile“.
  @risk %{
    key: "risk",
    title: "Risk",
    starter: true,
    asks_scope: false,
    layout: [
      %{"kind" => "own_rules", "size" => "row", "col" => 1, "row" => 1, "settings" => %{}},
      %{"kind" => "key_figures", "size" => "row", "col" => 1, "row" => 2, "settings" => %{}},
      %{"kind" => "crash_section", "size" => "row", "col" => 1, "row" => 3, "settings" => %{}},
      %{"kind" => "top_holdings", "size" => "row", "col" => 1, "row" => 4, "settings" => %{}},
      %{"kind" => "concentration", "size" => "row", "col" => 1, "row" => 5, "settings" => %{}},
      %{
        "kind" => "asset_class_limits",
        "size" => "row",
        "col" => 1,
        "row" => 6,
        "settings" => %{}
      }
    ]
  }

  # --- S32 W4 end ---

  # --- S32 S5 begin ---
  # The themes (I61; board 03 ①; Sprint 32 S5), offered in the gallery
  # beside the starters, never stored by the boot.
  #
  # „Krypto Lover“ (board 09's simulation): the cycle at XL, then the
  # performance and the tops and flops, the distance to the high and the
  # crashes at L; it asks for a scope, the operator's crypto view.
  @krypto_lover %{
    key: "krypto_lover",
    title: "Crypto Lover",
    starter: false,
    asks_scope: true,
    layout: [
      %{"kind" => "bitcoin_cycle", "size" => "XL", "col" => 1, "row" => 1, "settings" => %{}},
      %{"kind" => "performance", "size" => "L", "col" => 1, "row" => 5, "settings" => %{}},
      %{"kind" => "movers", "size" => "L", "col" => 7, "row" => 5, "settings" => %{}},
      %{"kind" => "distance_to_high", "size" => "L", "col" => 1, "row" => 9, "settings" => %{}},
      %{"kind" => "crashes", "size" => "L", "col" => 7, "row" => 9, "settings" => %{}}
    ]
  }

  # „Rücksetzer“ as board 11 draws it (D-15; the owner's description of
  # 2026-11-25; the name the owner's silence kept): the crash chart over
  # the year and pinned to 1M as the zoom, the crashes compared, the tops
  # and flops pinned to 1W and to 1M, the rebounders. The board's tops and
  # flops tiles are 6 × 4, the kind's L (it takes no M).
  @pullbacks %{
    key: "pullbacks",
    title: "Pullbacks",
    starter: false,
    asks_scope: false,
    layout: [
      %{"kind" => "crash_chart", "size" => "XL", "col" => 1, "row" => 1, "settings" => %{}},
      %{
        "kind" => "crash_chart",
        "size" => "L",
        "col" => 1,
        "row" => 5,
        "settings" => %{"period" => "1m"}
      },
      %{"kind" => "crashes", "size" => "L", "col" => 7, "row" => 5, "settings" => %{}},
      %{
        "kind" => "movers",
        "size" => "L",
        "col" => 1,
        "row" => 9,
        "settings" => %{"period" => "1w"}
      },
      %{
        "kind" => "movers",
        "size" => "L",
        "col" => 7,
        "row" => 9,
        "settings" => %{"period" => "1m"}
      },
      %{"kind" => "rebounders", "size" => "XL", "col" => 1, "row" => 13, "settings" => %{}}
    ]
  }

  # --- S32 S5 end ---

  @templates [
    @overview,
    # --- S32 W2 begin ---
    @allocation_targets,
    # --- S32 W2 end ---
    # --- S32 W3 begin ---
    @snapshots,
    # --- S32 W3 end ---
    # --- S32 W4 begin ---
    @risk,
    # --- S32 W4 end ---
    @krypto_lover,
    @pullbacks
  ]
  @by_key Map.new(@templates, &{&1.key, &1})

  @type t :: %{
          key: String.t(),
          title: String.t(),
          starter: boolean(),
          asks_scope: boolean(),
          layout: [map()]
        }

  @doc "The templates this release offers, in the menu's order."
  @spec templates() :: [t()]
  def templates, do: @templates

  @doc """
  The templates marked as starters (ADR-0062's amendment of 2026-11-25,
  point 5; Sprint 32 S3), in the menu's order: each is stored once, on the
  first start of the release that brings it. A pass that turns a screen
  into a starter only adds its template here with `starter: true`.
  """
  @spec starters() :: [t()]
  def starters, do: Enum.filter(@templates, & &1.starter)

  @doc """
  Of `templates`, the ones the gallery and the menu may offer (ADR-0062
  §3; the amendment of 2026-11-25, point 5): each whose kinds are all
  registered (`Portfolixir.Dashboards.Widgets`), in the order given. A
  template naming a kind its release does not build is left out.
  """
  @spec offered([t()]) :: [t()]
  def offered(templates) when is_list(templates) do
    Enum.filter(templates, fn template ->
      Enum.all?(template.layout, &match?({:ok, _}, Widgets.fetch(&1["kind"])))
    end)
  end

  @doc """
  The gallery's group of a template (board 03 ①): `"starter"`, a screen of
  today shipped as a starter dashboard, or `"theme"`.
  """
  @spec group(t()) :: String.t()
  def group(%{starter: true}), do: "starter"
  def group(_template), do: "theme"

  @doc "The template under `key`, matched as a string, or `:error`."
  @spec fetch(term()) :: {:ok, t()} | :error
  def fetch(key) when is_binary(key), do: Map.fetch(@by_key, key)
  def fetch(_key), do: :error

  @doc "The template's title in the current locale; `nil` for an unknown key."
  @spec title(term()) :: String.t() | nil
  def title("overview"), do: pgettext("dashboard template", "Overview")
  def title("krypto_lover"), do: pgettext("dashboard template", "Crypto Lover")
  def title("pullbacks"), do: pgettext("dashboard template", "Pullbacks")
  # --- S32 W2 begin ---
  def title("allocation_targets"), do: pgettext("dashboard template", "Allocation & targets")
  # --- S32 W2 end ---
  # --- S32 W3 begin ---
  def title("snapshots"), do: pgettext("dashboard template", "Snapshots")
  # --- S32 W3 end ---
  # --- S32 W4 begin ---
  def title("risk"), do: pgettext("dashboard template", "Risk")
  # --- S32 W4 end ---
  def title(_key), do: nil

  @doc """
  The template's line under its title in the gallery (board 03 ①), in the
  current locale; `nil` for an unknown key.
  """
  @spec subtitle(term()) :: String.t() | nil
  def subtitle("overview"), do: pgettext("dashboard template", "as today's start page")

  def subtitle("krypto_lover"),
    do: pgettext("dashboard template", "cycle, halving, a crypto view")

  def subtitle("pullbacks"),
    do: pgettext("dashboard template", "the falls compared, short tops and flops, rebounders")

  # --- S32 W2 begin ---
  def subtitle("allocation_targets"),
    do: pgettext("dashboard template", "as Wealth's tab today")

  # --- S32 W2 end ---

  # --- S32 W3 begin ---
  def subtitle("snapshots"), do: pgettext("dashboard template", "as Wealth's tab today")

  # --- S32 W3 end ---

  # --- S32 W4 begin ---
  def subtitle("risk"), do: pgettext("dashboard template", "as Wealth's tab today")

  # --- S32 W4 end ---

  def subtitle(_key), do: nil

  @doc """
  The names of the view a template that asks for a scope suggests (board
  03 ②, where „Krypto Lover“'s dialog shows „Krypto ▾“; the S32 closing
  act): the name in every language the release speaks („Crypto“,
  „Krypto“), since a view's name is the operator's word in whichever
  language they wrote it; the dialog matches them against the stored
  views' names, ignoring case, to preselect the first that matches. `nil`
  for a template that suggests none.
  """
  @spec suggested_scope(term()) :: [String.t()] | nil
  def suggested_scope("krypto_lover"),
    do: in_every_locale(fn -> pgettext("dashboard template scope", "Crypto") end)

  def suggested_scope(_key), do: nil

  defp in_every_locale(fun) do
    PortfolixirWeb.Gettext
    |> Gettext.known_locales()
    |> Enum.map(&Gettext.with_locale(PortfolixirWeb.Gettext, &1, fun))
    |> then(&[fun.() | &1])
    |> Enum.uniq()
  end
end
