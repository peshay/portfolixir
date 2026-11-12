defmodule PortfolixirWeb.Components.StackedChartBarTest do
  # The stacked chart's bar (`StackedChart.bar/1`), the first user of the
  # shared bar of labelled controls (`ControlBar.bar/1`; issue 1435, Sprint
  # 29 L1; inventory §1 row 1 and §2 "Extract"). Its markup before the
  # extraction is kept below as it rendered on the commit the lane started
  # from; the bar must render the same elements, attributes and text, the
  # component's class names in place of the bar's own being the one
  # deliberate change, each named in `@renames`. Where the boxes land, before
  # and after, is pinned by `test/browser/control_bar_test.exs`.
  use ExUnit.Case, async: true

  alias PortfolixirWeb.Portfolio.StackedChart

  @paths %{
    total: "/portfolio?level=total",
    category: "/portfolio?level=category&tree=7",
    security: "/portfolio?level=security&tree=7",
    size: "/portfolio?level=category&tree=7&sort=size",
    change: "/portfolio?level=category&tree=7&sort=change"
  }

  @classifications [%{id: 7, key: nil, name: "Strategy"}, %{id: 8, key: "asset_class", name: "x"}]

  # The bar at the level Categories under a filter, sorted by change: the
  # breadcrumb and all three groups.
  @category_before """
  <div class="stack-bar" data-role="stack-bar">
    <nav class="stack-crumbs" data-role="stack-crumbs" aria-label="Stack">
      <a href="/portfolio?level=category&amp;tree=7" data-phx-link="patch" data-phx-link-state="push">All categories</a>
      <span class="stack-crumbs__sep" aria-hidden="true">›</span>
      <span id="stack-crumbs-current" aria-current="location" tabindex="-1">Growth</span>
    </nav>
    <div class="stack-bar__controls">
      <span class="stack-bar__group">
      <span class="stack-bar__label" id="stack-level-label">Level</span>
      <div class="segmented-control" data-role="stack-level" role="group" aria-labelledby="stack-level-label">
        <a href="/portfolio?level=total" data-phx-link="patch" data-phx-link-state="push" class="segmented-control__option" data-level="total">
          Total
        </a><a href="/portfolio?level=category&amp;tree=7" data-phx-link="patch" data-phx-link-state="push" class="segmented-control__option is-active" aria-current="true" data-level="category">
          Categories
        </a><a href="/portfolio?level=security&amp;tree=7" data-phx-link="patch" data-phx-link-state="push" class="segmented-control__option" data-level="security">
          Securities
        </a>
      </div>
      </span>
      <form id="stack-classification-form" class="stack-bar__tree" phx-change="select_stack_classification">
        <label for="stack-classification">Classification</label>
        <select id="stack-classification" name="tree">
          <option value="7" selected>
            Strategy
          </option><option value="8">
            Asset class
          </option>
        </select>
      </form>
      <span class="stack-bar__group">
      <span class="stack-bar__label" id="stack-sort-label">
        Sort
      </span>
      <div class="segmented-control" data-role="stack-sort" role="group" aria-labelledby="stack-sort-label">
        <a href="/portfolio?level=category&amp;tree=7&amp;sort=size" data-phx-link="patch" data-phx-link-state="push" class="segmented-control__option" data-sort="size">
          Size
        </a><a href="/portfolio?level=category&amp;tree=7&amp;sort=change" data-phx-link="patch" data-phx-link-state="push" class="segmented-control__option is-active" aria-current="true" data-sort="change">
          Change
        </a>
      </div>
      </span>
    </div>
  </div>
  """

  # The bar at the level Total: no breadcrumb, the level alone.
  @total_before """
  <div class="stack-bar" data-role="stack-bar">
    <div class="stack-bar__controls">
      <span class="stack-bar__group">
      <span class="stack-bar__label" id="stack-level-label">Level</span>
      <div class="segmented-control" data-role="stack-level" role="group" aria-labelledby="stack-level-label">
        <a href="/portfolio?level=total" data-phx-link="patch" data-phx-link-state="push" class="segmented-control__option is-active" aria-current="true" data-level="total">
          Total
        </a><a href="/portfolio?level=category&amp;tree=7" data-phx-link="patch" data-phx-link-state="push" class="segmented-control__option" data-level="category">
          Categories
        </a><a href="/portfolio?level=security&amp;tree=7" data-phx-link="patch" data-phx-link-state="push" class="segmented-control__option" data-level="security">
          Securities
        </a>
      </div>
      </span>
    </div>
  </div>
  """

  # The deliberate changes, and only these: the bar's own classes become the
  # component's (the root takes its fold and floor, 760 and 330 px as the
  # bar's container queries had them), the classification's form becomes a
  # group of the component, and its label, styled before as
  # `.stack-bar__tree label`, carries the component's label class.
  @renames %{
    "stack-bar" => ["control-bar", "control-bar--fold-760", "control-bar--floor-330"],
    "stack-bar__controls" => ["control-bar__controls"],
    "stack-bar__group" => ["control-bar__group"],
    "stack-bar__label" => ["control-bar__label"],
    "stack-bar__tree" => ["control-bar__group"]
  }

  defp render_bar(stack, crumbs, classification_id) do
    %{
      __changed__: nil,
      stack: stack,
      paths: @paths,
      crumbs: crumbs,
      classifications: @classifications,
      classification_id: classification_id
    }
    |> StackedChart.bar()
    |> Phoenix.LiveViewTest.rendered_to_string()
  end

  # The DOM as elements, sorted attributes, class lists and trimmed text:
  # whitespace between elements carries nothing in the bar's flex and grid
  # rows, so it is not compared.
  defp tree(html), do: html |> LazyHTML.from_fragment() |> LazyHTML.to_tree() |> normalize()

  defp normalize(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, fn
      {tag, attrs, children} ->
        [{tag, attrs |> Enum.map(&attribute/1) |> Enum.sort(), normalize(children)}]

      text when is_binary(text) ->
        case text |> String.split() |> Enum.join(" ") do
          "" -> []
          collapsed -> [collapsed]
        end

      {:comment, _} ->
        []
    end)
  end

  defp attribute({"class", value}), do: {"class", value |> String.split() |> Enum.sort()}
  defp attribute(pair), do: pair

  defp renamed(nodes) do
    Enum.map(nodes, fn
      {"label", attrs, children} = node ->
        if {"for", "stack-classification"} in attrs,
          do:
            {"label", Enum.sort([{"class", ["control-bar__label"]} | attrs]), renamed(children)},
          else: node

      {tag, attrs, children} ->
        {tag, Enum.map(attrs, &rename/1), renamed(children)}

      text ->
        text
    end)
  end

  defp rename({"class", classes}),
    do: {"class", classes |> Enum.flat_map(&Map.get(@renames, &1, [&1])) |> Enum.sort()}

  defp rename(pair), do: pair

  # User story (issue 1435, Sprint 29 L1):
  # As the operator choosing the stack's level, classification and sort,
  # I want the stacked chart's bar to stay exactly as it is when it becomes
  # the shared component's first user,
  # so that the extraction changes no element, link, label or name on the
  # screen.
  #
  # Acceptance criteria:
  # - At the level Categories under a filter, and at the level Total, the
  #   bar renders the elements, attributes and text it rendered before the
  #   component (`@category_before`, `@total_before`), with the component's
  #   classes in place of the bar's own as `@renames` lists them, and with
  #   nothing else changed.
  # - The breadcrumb, the ids and `aria-labelledby` the browser walks and the
  #   LiveView tests read (`stack-level-label`, `stack-classification`,
  #   `stack-sort-label`, `data-role='stack-bar'`) keep their places.
  test "the stacked chart's bar renders today's markup, in the component's classes" do
    category =
      render_bar(
        %{level: :category, sort: :change, category: nil},
        [{"All categories", "/portfolio?level=category&tree=7"}, {"Growth", nil}],
        7
      )

    assert tree(category) == @category_before |> tree() |> renamed()

    total = render_bar(%{level: :total, sort: :size, category: nil}, [], nil)
    assert tree(total) == @total_before |> tree() |> renamed()
  end
end
