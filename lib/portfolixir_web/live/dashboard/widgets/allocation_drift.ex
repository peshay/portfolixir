defmodule PortfolixirWeb.Dashboard.Widgets.AllocationDrift do
  @moduledoc """
  The widget „Allokation und Drift“ `allocation_drift` (ADR-0062 §12;
  planning board `ux-design-2026-11-21-sprint31/01` ①; idea boards
  `ux-design-2026-11-21-idea-i56` 01, 03 and 06; Sprint 31 D4).

  Every figure is `Portfolixir.Portfolios.Allocation.for_portfolio/3` for
  the first portfolio, the default steering tree (the one Wealth's
  „Allokation & Ziele“ opens on) and the widget's view, the read
  `GET /api/v1/portfolios/:portfolio_id/allocation?classification_id=&view=`
  answers:

    * the drift table, M and T alike — each top-level category of the tree
      and cash, its actual weight („Ist“), the target its drift is
      measured against („Soll“) and its drift (ADR-0023: actual − target,
      positive overweight) with a bar around zero, scaled to the largest
      drift listed. For a plan whose top level allocates less than 100 %
      that target is the entered one divided by the top-level sum
      (ADR-0040 §2, the read's `drift_basis` `allocated_portion`), and the
      basis line says so, so a row's Ist − Soll is its drift (Sprint 31
      closing act, money lens MO2);
    * „Rechnerisch zum Soll“ — the display-only arithmetic of ADR-0023 for
      the rows off target (`off_target/1`, the one rule „Abseits des
      Ziels“ applies too: every level of the tree and cash, a drift of
      ±5 pp or more by `Allocation.drift_at_least?/2`, inclusive as the
      API's `min_drift=`; Sprint 31 closing act, money lens MO4): the
      amount that would close each gap, the row's `drift_value` with its
      sign turned, in the base currency, stated as arithmetic, never as
      an order;
    * **compact** (board 06) — one row per targeted line, the largest
      drift first: its name, „Ist · Soll“ under it, the drift as the figure.

  The footer counts the rows off target and leads to where the targets
  are edited, Wealth's „Allokation & Ziele“. With several portfolios the
  basis line names the one it reads, the first, as Wealth opens on it.
  Without a tree, a portfolio or an active plan the widget says so in
  one quiet line.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.Dashboards.Widgets
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Allocation
  alias Portfolixir.Portfolios.Targets
  alias PortfolixirWeb.ClassificationName
  alias PortfolixirWeb.Dashboard.Widget
  alias PortfolixirWeb.Format

  @threshold Decimal.new("0.05")
  @bar_reach 45

  # -- the read -----------------------------------------------------------------

  @doc """
  The widget's read, in the page's background task: the allocation of the
  first portfolio in the default tree for the scope `scope_id` (nil for
  Everything; a vanished view reads Everything), with the active plan's
  name. `%{state: :no_tree}` or `%{state: :no_portfolio}` when there is
  nothing to read.
  """
  @spec read(integer() | nil) :: map()
  def read(scope_id) do
    with {:tree, %{} = tree} <- {:tree, Classifications.default_classification()},
         {:portfolio, %{} = portfolio} <- {:portfolio, Portfolios.first_portfolio()} do
      view = scope_id && Buckets.get_view(scope_id)
      view_id = view && view.id

      case Allocation.for_portfolio(portfolio.id, tree.id, view: view_id) do
        {:ok, allocation} ->
          %{
            state: :ok,
            allocation: allocation,
            portfolio_id: portfolio.id,
            # Named on the widget only where another portfolio exists (MO4).
            portfolio_name: if(length(Portfolios.list_portfolios()) > 1, do: portfolio.name),
            view_id: view_id,
            tree: %{key: tree.key, name: tree.name},
            plan_names: plan_names(portfolio.id, tree.id, view_id)
          }

        {:error, :view_not_found} ->
          read(nil)

        {:error, _reason} ->
          %{state: :no_tree}
      end
    else
      {:tree, nil} -> %{state: :no_tree}
      {:portfolio, nil} -> %{state: :no_portfolio}
    end
  end

  defp plan_names(portfolio_id, tree_id, view_id) do
    portfolio_id
    |> Targets.list_plans(classification_id: tree_id, view: view_id)
    |> Enum.filter(&(&1.status == "active"))
    |> Enum.map(& &1.name)
  end

  @doc """
  The rows the table draws: the tree's top-level categories in the read's
  order, then cash unless the tree distributes it into its categories.
  """
  @spec rows(map()) :: [map()]
  def rows(%{categories: categories, cash: cash}) do
    top =
      categories
      |> Enum.filter(&(&1.depth == 0))
      |> Enum.map(
        &Map.take(&1, [:name, :actual_weight, :target_weight, :drift_weight, :drift_value])
      )

    if Map.get(cash, :distributed, false) do
      top
    else
      cash_row =
        cash
        |> Map.take([:actual_weight, :target_weight, :drift_weight, :drift_value])
        |> Map.put(:name, :cash)

      top ++ [cash_row]
    end
  end

  @doc """
  The target a row's drift is measured against: its actual weight minus
  its drift, which is the entered target for a full plan and the target
  divided by the top-level sum for one that allocates less (ADR-0040 §2).
  """
  @spec drift_target(map()) :: Decimal.t() | nil
  def drift_target(%{actual_weight: %Decimal{} = actual, drift_weight: %Decimal{} = drift}),
    do: Decimal.sub(actual, drift)

  def drift_target(row), do: Map.get(row, :target_weight)

  @doc """
  The rows of an allocation read that count as off target — the one rule
  both of the dashboard's drift widgets apply, „Abseits des Ziels“ per
  portfolio and „Allokation und Drift“ for its own (Sprint 31 closing act,
  money lens MO4): every category at every level of the tree, in the
  read's order, then cash unless the tree distributes it; each with a
  target, its drift meeting `threshold/0` by
  `Portfolixir.Portfolios.Allocation.drift_at_least?/2`, inclusive, as the
  API's `min_drift=` selects. Cash carries the name `:cash`.
  """
  @spec off_target(map()) :: [map()]
  def off_target(%{categories: categories, cash: cash}) do
    cash_rows = if Map.get(cash, :distributed, false), do: [], else: [Map.put(cash, :name, :cash)]

    Enum.filter(
      categories ++ cash_rows,
      &(targeted?(&1) and Allocation.drift_at_least?(&1, @threshold))
    )
  end

  @doc "The drift that counts as off target: 5 pp, as a weight."
  @spec threshold() :: Decimal.t()
  def threshold, do: @threshold

  @doc "The threshold in percentage points, as the screens say it: `\"5\"`."
  @spec threshold_pp() :: String.t()
  def threshold_pp,
    do: @threshold |> Decimal.mult(100) |> Decimal.normalize() |> Decimal.to_string(:normal)

  defp targeted?(%{target_weight: %Decimal{} = target}), do: Decimal.compare(target, 0) == :gt
  defp targeted?(_row), do: false

  # -- the widget ---------------------------------------------------------------

  attr(:item, :map, required: true)
  attr(:card, :any, required: true, doc: "nil while the read runs, :error, or `read/1`'s answer")
  attr(:scope_label, :string, default: nil)

  @doc "The widget „Allokation und Drift“ with its compact form."
  def widget(assigns) do
    assigns =
      assigns
      |> assign(:uid, assigns.item.uid)
      |> assign(:ready, match?(%{state: :ok}, assigns.card))
      |> then(fn assigns ->
        if assigns.ready do
          rows = rows(assigns.card.allocation)

          assign(assigns,
            rows: rows,
            beyond: off_target(assigns.card.allocation),
            plan?: assigns.card.allocation.has_plan
          )
        else
          assign(assigns, rows: [], beyond: [], plan?: false)
        end
      end)

    ~H"""
    <Widget.frame
      id={"dashboard-allocation-drift" <> @uid}
      item={@item}
      title={Widgets.title("allocation_drift")}
      scope_label={foot_label(@ready, @plan?, @beyond, @scope_label)}
      full_href="/portfolio?tab=allocation"
      full_label={gettext("Edit targets →")}
      full_role="allocation-edit-targets"
    >
      <:info>
        <%= gettext("Drift is the actual weight minus the target weight of the active plan, per category of the steering tree; a category without a target is not listed.") %>
      </:info>
      <:info>
        <%= gettext("Where the plan's top-level targets sum to less than 100%, the drift is measured against the allocated portion: each target is divided by that sum, and the target column shows the divided target.") %>
      </:info>
      <:info>
        <%= gettext("Actual: the category's value ÷ the value of the portfolio's holdings and cash in the view, each priced by its latest quote, as Wealth's allocation reads it.") %>
      </:info>
      <:info>
        <%= gettext("“Arithmetically to target” is the drift in money with its sign turned: the amount that would close the gap at today's values. Display only: no order, no fees or taxes.") %>
      </:info>
      <:shared>
        <p :if={is_nil(@card)} class="section-skeleton" aria-busy="true" data-role="allocation-drift-skeleton"></p>
        <p :if={@card == :error} class="hint" data-role="allocation-drift-failed">
          <%= gettext("Couldn't load the allocation.") %>
        </p>
        <p :if={match?(%{state: :no_tree}, @card)} class="hint" data-role="allocation-drift-empty">
          <%= gettext("No classification to steer by yet.") %>
        </p>
        <p :if={match?(%{state: :no_portfolio}, @card)} class="hint" data-role="allocation-drift-empty">
          <%= gettext("No portfolio yet.") %>
        </p>
        <p :if={@ready} class="hint" data-role="allocation-drift-basis">
          <%= basis_line(@card, @plan?) %>
        </p>
      </:shared>
      <table :if={@ready and @rows != []} class="data-table widget-drift-table" data-role="allocation-drift-table">
        <thead>
          <tr>
            <th scope="col"><%= gettext("Category") %></th>
            <th scope="col" class="num"><%= gettext("Actual") %></th>
            <th scope="col" class="num"><%= gettext("Target") %></th>
            <th scope="col" class="num"><%= gettext("Drift") %></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @rows} data-role="allocation-drift-row" data-name={row_name(row)}>
            <th scope="row"><%= row_name(row) %></th>
            <td class="num" data-role="drift-actual"><%= weight(row.actual_weight) %></td>
            <td class="num" data-role="drift-target"><%= if targeted?(row), do: weight(drift_target(row)), else: "—" %></td>
            <td class="num widget-drift-table__drift">
              <span :if={targeted?(row)} class="drift-bar" aria-hidden="true">
                <span
                  class={["drift-bar__fill", side(row.drift_weight)]}
                  style={"width: #{bar_width(row.drift_weight, @rows)}%"}
                >
                </span>
              </span>
              <span class={sign_class(row.drift_weight)} data-role="drift-points"><%= if targeted?(row), do: points(row.drift_weight), else: "—" %></span>
            </td>
          </tr>
        </tbody>
      </table>
      <p :if={@beyond != []} class="hint widget-drift-hint" data-role="allocation-drift-arithmetic">
        <strong><%= gettext("Arithmetically to target") %></strong>
        (<%= gettext("display only, no order") %>):
        <%= for {row, index} <- Enum.with_index(@beyond) do %><%= if index > 0, do: ", " %><span data-role="drift-arithmetic" data-name={row_name(row)}><%= row_name(row) %> ≈ <span class="num"><%= corrective(row) %></span> <%= @card.allocation.base_currency %></span><% end %>
      </p>
      <:compact>
        <p :if={@ready} class="widget-compact-note" data-compact-role="allocation-drift-threshold">
          <%= gettext("A drift of ±%{pp} pp or more counts as off target", pp: threshold_pp()) %>
        </p>
        <Widget.row
          :for={row <- compact_rows(@rows)}
          href="/portfolio?tab=allocation"
          data-compact-role="allocation-drift-row"
          data-name={row_name(row)}
        >
          <:name><%= row_name(row) %></:name>
          <:sub><%= weight(row.actual_weight) %> · <%= gettext("target %{weight}", weight: weight(drift_target(row))) %></:sub>
          <:figure><span class={sign_class(row.drift_weight)}><%= points(row.drift_weight) %></span></:figure>
        </Widget.row>
        <p :if={@beyond != []} class="widget-compact-note" data-compact-role="allocation-drift-arithmetic">
          <%= gettext("Arithmetically to target, display only:") %>
          <%= for {row, index} <- Enum.with_index(@beyond) do %><%= if index > 0, do: ", " %><%= row_name(row) %> ≈ <span class="num"><%= corrective(row) %></span> <%= @card.allocation.base_currency %><% end %>
        </p>
      </:compact>
    </Widget.frame>
    """
  end

  defp foot_label(true, true, beyond, scope_label) do
    count =
      ngettext(
        "%{count} at ±%{pp} pp or more",
        "%{count} at ±%{pp} pp or more",
        length(beyond),
        pp: threshold_pp()
      )

    if scope_label, do: count <> " · " <> scope_label, else: count
  end

  defp foot_label(_ready, _plan?, _beyond, scope_label), do: scope_label

  defp basis_line(card, true) do
    tree = ClassificationName.display(card.tree)

    plan =
      case card.plan_names do
        [name] -> gettext("Plan “%{plan}” on %{tree}", plan: name, tree: tree)
        [] -> gettext("Targets on %{tree}", tree: tree)
        _several -> gettext("Several active plans on %{tree}", tree: tree)
      end

    portfolio(card) <> plan <> portion(card.allocation)
  end

  defp basis_line(card, false),
    do:
      portfolio(card) <>
        gettext("No active plan on %{tree}: the actual weights alone.",
          tree: ClassificationName.display(card.tree)
        )

  # With several portfolios, the one the widget reads (MO4).
  defp portfolio(%{portfolio_name: name}) when is_binary(name),
    do: gettext("Portfolio %{name}", name: name) <> " · "

  defp portfolio(_card), do: ""

  # ADR-0040 §2, as Wealth's basis line says it: a plan whose top level
  # allocates less than 100 % measures target and drift against that
  # portion (MO2).
  defp portion(%{drift_basis: "allocated_portion", top_level_target_sum: %Decimal{} = sum}),
    do:
      " · " <>
        gettext(
          "Σ target top level %{sum}: target and drift against the allocated portion",
          sum: weight(sum)
        )

  defp portion(_allocation), do: ""

  # Board 06: the targeted rows, the largest drift first.
  defp compact_rows(rows) do
    rows
    |> Enum.filter(&targeted?/1)
    |> Enum.sort_by(&Decimal.abs(&1.drift_weight), {:desc, Decimal})
  end

  defp row_name(%{name: :cash}), do: gettext("Cash")
  defp row_name(%{name: name}), do: name

  defp weight(%Decimal{} = value), do: Format.percent(value) <> "%"
  defp weight(_none), do: "—"

  @doc "A drift in signed percentage points, as the compact rows draw it."
  @spec points(Decimal.t()) :: String.t()
  def points(drift_weight) do
    sign =
      case Format.displayed_percent_sign(drift_weight) do
        :negative -> "−"
        :positive -> "+"
        _zero -> ""
      end

    gettext("%{pp} pp", pp: sign <> Format.percent(Decimal.abs(drift_weight)))
  end

  @doc """
  The amount that would close a row's gap (ADR-0023's arithmetic): its
  `drift_value` with the sign turned, signed, two places; the privacy
  mode's mask while it is on (`PortfolixirWeb.Format.signed_decimal/3`),
  so it is rendered, never concatenated.
  """
  @spec corrective(map()) :: String.t() | struct()
  def corrective(row), do: Format.signed_decimal(Decimal.negate(row.drift_value), 2)

  defp side(drift_weight),
    do: if(Decimal.compare(drift_weight, 0) == :lt, do: "is-under", else: "is-over")

  defp bar_width(drift_weight, rows) do
    worst =
      rows
      |> Enum.filter(&targeted?/1)
      |> Enum.map(&Decimal.abs(&1.drift_weight))
      |> Enum.max(Decimal, fn -> Decimal.new(0) end)

    if Decimal.compare(worst, 0) == :gt do
      drift_weight
      |> Decimal.abs()
      |> Decimal.div(worst)
      |> Decimal.mult(@bar_reach)
      |> Decimal.round(1)
      |> Decimal.to_string(:normal)
    else
      "0"
    end
  end

  # As „Abseits des Ziels“ colours it (#1149): an underweight drift as
  # displayed is negative; an overweight one keeps the text colour, its
  # sign and the bar's side say the direction.
  defp sign_class(value) do
    if Format.displayed_percent_sign(value) == :negative, do: "is-negative", else: nil
  end
end
