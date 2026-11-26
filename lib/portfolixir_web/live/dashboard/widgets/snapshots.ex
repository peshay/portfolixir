defmodule PortfolixirWeb.Dashboard.Widgets.Snapshots do
  @moduledoc """
  The widget „Snapshots“ `snapshots` (ADR-0062 §12; ADR-0027; planning
  board `ux-design-2026-11-21-sprint31/01` ①: „01.11.2026 · letzter von 14
  · seitdem +2,3 %“ with a sparkline; idea boards
  `ux-design-2026-11-21-idea-i56` 03 and 06; Sprint 31 D4).

  Its figures are two reads the Snapshots page and the agent make:

    * `Portfolixir.Portfolios.Snapshots.list_snapshots/1`, the list
      `GET /api/v1/snapshots` answers, newest as-of first: the latest
      snapshot's date and name, and how many there are;
    * `Portfolixir.Portfolios.SnapshotComparison.for_snapshot/2` for the
      latest snapshot in the first portfolio (the pairing the Snapshots
      page uses), the read
      `GET /api/v1/portfolios/:portfolio_id/snapshots/:id/comparison`
      answers: the scope's real TTWROR since the as-of date („seitdem“)
      and its daily chain, the sparkline.

  S and W draw the same figures, W with the snapshot's name beside them;
  the compact form (board 06) is the count and the latest date, one row
  each. „Vergleichen →“ opens the comparison on the Snapshots page. With no
  snapshot the widget says so in one quiet line.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Dashboards.Widgets
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.SnapshotComparison
  alias Portfolixir.Portfolios.Snapshots
  alias PortfolixirWeb.Dashboard.Widget
  alias PortfolixirWeb.Dashboard.Widgets.Line
  alias PortfolixirWeb.Format

  # -- the read -----------------------------------------------------------------

  @doc """
  The widget's read, in the page's background task: the snapshots' count,
  the latest one, and its comparison in the first portfolio (`nil` when
  there is no portfolio or the comparison refuses).
  """
  @spec read() :: map()
  def read do
    case Snapshots.list_snapshots() do
      [] ->
        %{count: 0, latest: nil, comparison: nil}

      [latest | _older] = snapshots ->
        %{count: length(snapshots), latest: latest, comparison: comparison(latest)}
    end
  end

  defp comparison(latest) do
    with %{id: portfolio_id} <- Portfolios.first_portfolio(),
         {:ok, comparison} <- SnapshotComparison.for_snapshot(latest, portfolio_id) do
      comparison
    else
      _none -> nil
    end
  end

  # -- the widget ---------------------------------------------------------------

  attr(:item, :map, required: true)
  attr(:card, :any, required: true, doc: "nil while the read runs, :error, or `read/0`'s answer")

  @doc "The widget „Snapshots“ with its compact form."
  def widget(assigns) do
    assigns =
      assigns
      |> assign(:uid, assigns.item.uid)
      |> assign(:latest, match?(%{latest: %{}}, assigns.card) && assigns.card.latest)
      |> assign(:comparison, is_map(assigns.card) && assigns.card.comparison)

    ~H"""
    <Widget.frame
      id={"dashboard-snapshots" <> @uid}
      item={@item}
      title={Widgets.title("snapshots")}
      full_href={compare_href(@latest)}
      full_label={if @latest, do: gettext("Compare →"), else: gettext("To the snapshots →")}
      full_role="snapshots-compare"
    >
      <:info>
        <%= gettext("A snapshot marks the holdings of a day; nothing is copied. “Since then” is the scope's real TTWROR from the snapshot's date to today, in the first portfolio, as the Snapshots page compares it.") %>
      </:info>
      <:shared>
        <p :if={is_nil(@card)} class="section-skeleton" aria-busy="true" data-role="snapshots-skeleton"></p>
        <p :if={@card == :error} class="hint" data-role="snapshots-failed">
          <%= gettext("Couldn't load the snapshots.") %>
        </p>
        <p :if={match?(%{count: 0}, @card)} class="hint" data-role="snapshots-empty">
          <%= gettext("No snapshot yet.") %>
        </p>
      </:shared>
      <%!-- Sprint 32 L2 (board 07 ① 5): the anatomy's figure, 28 px at
           S, the 34 px hero at M. --%>
      <div :if={@latest} class="widget-snapshots" data-role="snapshots-figure">
        <Widget.figure size={if @item.size == "M", do: :m, else: :s}>
          <span data-role="snapshots-latest"><%= Format.date(@latest.as_of) %></span>
          <:sub>
            <span data-role="snapshots-count"><%= ngettext("the only one", "latest of %{count}", @card.count) %></span>
            <span :if={@comparison && @comparison.real_ttwror}>
              · <%= gettext("since then") %>
              <span class={sign_class(@comparison.real_ttwror)} data-role="snapshots-since"><%= percent(@comparison.real_ttwror) %></span>
            </span>
            <span :if={@item.size == "M"} data-role="snapshots-name">· <bdi><%= @latest.name %></bdi></span>
          </:sub>
        </Widget.figure>
        <Line.sparkline
          :if={@comparison}
          values={real_chain(@comparison)}
          role="snapshots-spark"
        />
      </div>
      <:compact>
        <Widget.row :if={@latest} href="/snapshots" data-compact-role="snapshots-count">
          <:name><%= gettext("Snapshots") %></:name>
          <:figure><%= @card.count %></:figure>
        </Widget.row>
        <Widget.row :if={@latest} href={compare_href(@latest)} data-compact-role="snapshots-latest">
          <:name><%= Format.date(@latest.as_of) %></:name>
          <:sub><%= gettext("latest snapshot") %></:sub>
          <:figure :if={@comparison && @comparison.real_ttwror}>
            <span class={sign_class(@comparison.real_ttwror)}><%= percent(@comparison.real_ttwror) %></span>
          </:figure>
          <:figure_sub :if={@comparison && @comparison.real_ttwror}><%= gettext("since then") %></:figure_sub>
        </Widget.row>
      </:compact>
    </Widget.frame>
    """
  end

  # The real side's daily chain (1 + TTWROR since the as-of date), the
  # days it has a factor for.
  defp real_chain(comparison) do
    comparison.series
    |> Enum.map(& &1.real_indexed)
    |> Enum.filter(&match?(%Decimal{}, &1))
  end

  defp compare_href(%{id: id}), do: "/snapshots?snapshot=#{id}"
  defp compare_href(_none), do: "/snapshots"

  defp percent(%Decimal{} = value), do: Format.signed_percent(value) <> "%"

  defp sign_class(value) do
    case Format.displayed_percent_sign(value) do
      :positive -> "is-positive"
      :negative -> "is-negative"
      :zero -> "is-flat"
      nil -> nil
    end
  end
end
