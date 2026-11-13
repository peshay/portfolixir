defmodule Portfolixir.Invariants.ControlBarLabelledControlsTest do
  use ExUnit.Case, async: true

  # Issue 1435 (3), Sprint 29 L4 (DESIGN.md, amendment of 2026-11-08,
  # "Labelled controls start on one edge"; board
  # `ux-design-2026-11-12-sprint29/06-control-bar` and its inventory §1): a
  # bar of labelled controls is one component, `PortfolixirWeb.ControlBar.bar/1`.
  # The browser walk (L3) measures the bars a page renders on the review
  # seed; this check reads every template of the web layer, so a labelled
  # control on a page the seed does not reach, or in a state the walk does
  # not open, cannot be built beside the component either.
  #
  # It reads every `~H` template under lib/portfolixir_web/ as a tree of
  # tags and finds each **control family**: a select, a segmented control
  # (class `segmented-control`), a chip family (class `filter-chips` or
  # `filter-chips__group`, `ChangedSince.chips` without a bar's `label_id`,
  # or a family's name, `filter-chips__family`, whose chips a function
  # component draws). A family is **labelled** when a visible label belongs
  # to it (visible: neither it nor an ancestor `visually-hidden` or
  # `sr-only`), by any of
  #
  #   1. `aria-labelledby` naming the id of a visible element;
  #   2. a visible `<label for>` naming the select's id;
  #   3. a visible `<label>` around it that carries text of its own;
  #   4. a family's name inside it, or the name standing for it;
  #   5. its place: what stands right before it is text, or an element
  #      that carries visible text and holds no control (a label linked to
  #      nothing, or one split across elements);
  #   6. inside the component, its group's `label`.
  #
  # A labelled family inside `<ControlBar.bar>` is the component's; one
  # outside it fails the check unless an exception below names it with its
  # reason. The families the inventory found without a visible label are
  # registered too, so one that gains a label fails here: it belongs on the
  # component then.
  #
  # The check is lexical, so its limits are named: markup built as a string
  # (`~s[<select ...>]`) is not read; a label set in CSS (`::before`) is not
  # seen (the walk sees it); a family labelled from another file's template
  # through an id is read as unlabelled.
  #
  # Runs in the test job: it reads files and needs no browser.

  @web_glob "lib/portfolixir_web/**/*.ex"

  @void ~w(area base br col embed hr img input link meta source track wbr)

  # Elements that can stand as a label beside a control (a `div` or a `p`
  # only with a class that says so: a paragraph before a control is prose).
  @label_tags ~w(span label strong b em small i dt legend)

  # Classes that hide an element from the eye, not from a screen reader.
  @hidden_classes ~w(visually-hidden sr-only)

  # Elements that are controls themselves, never a label.
  @control_tags ~w(select input button textarea a .link)

  @no_visible_label "no visible label: an aria-label or a visually hidden label only, so not a " <>
                      "labelled control (inventory §1, \"Named in the issue, but not labelled bars\")"

  @form_field "a form's fields, each label above its field, one field under another or in a " <>
                "grid of fields: a form, not a bar of controls side by side"

  @single "one labelled select on a line of its own, with no second labelled control beside " <>
            "or under it to share an edge with: not a bar"

  @sheet "the phone's filter sheet: every family under its own name in one column, all at " <>
           "one edge by construction (labels above, B; inventory §1 rows 4 and 6)"

  # Registered exceptions: %{file, match, reason}, plus `labelled: false`
  # for a family registered because it has no visible label. `file` is
  # relative to lib/portfolixir_web/; `match` is text on the opening tag of
  # the family or of one of its ancestors in the template. An entry that
  # matches no family of its kind fails as stale; one without a reason
  # fails.
  @exceptions [
    # The bars the inventory found without a visible label (§1, "Named in
    # the issue, but not labelled bars"): each must stay without one.
    %{
      file: "live/income_live.ex",
      match: ~s(data-role="cashflow-facets"),
      labelled: false,
      reason: @no_visible_label
    },
    %{
      file: "live/portfolio_live.ex",
      match: ~s(data-role="chart-series"),
      labelled: false,
      reason: @no_visible_label
    },
    %{
      file: "live/portfolio_live.ex",
      match: ~s(data-role="period-tokens"),
      labelled: false,
      reason: @no_visible_label
    },
    %{
      file: "live/portfolio_live.ex",
      match: ~s|aria-label={gettext("Allocation view")}|,
      labelled: false,
      reason: @no_visible_label
    },
    %{
      file: "live/portfolio_live.ex",
      match: ~s(id="allocation-classification"),
      labelled: false,
      reason: @no_visible_label
    },
    %{
      file: "live/tax_live.ex",
      match: ~s(data-role="tax-holders"),
      labelled: false,
      reason: @no_visible_label
    },
    %{
      file: "live/tax_live.ex",
      match: ~s(data-role="tax-years"),
      labelled: false,
      reason: @no_visible_label
    },
    %{
      file: "live/predictions_live.ex",
      match: ~s(id="prediction-status-chips"),
      labelled: false,
      reason: @no_visible_label
    },
    # The phone's filter sheets, and the named family they use.
    %{file: "live/securities_live.ex", match: ~s(class="filter-sheet__family"), reason: @sheet},
    %{
      file: "live/transaction_management_live.ex",
      match: ~s(class="filter-sheet__families"),
      reason: @sheet
    },
    %{
      file: "components/changed_since.ex",
      match: ~s(class="filter-chips__group"),
      reason:
        "ChangedSince.chips/1 without a bar's label_id names its own family, as the phone's " <>
          "filter sheets use it; on a bar it takes the bar's label (label_id)"
    },
    # Forms: fields under one another, not bars.
    %{
      file: "live/portfolio_accounts/account_form_dialog.ex",
      match: ~s(class="form-grid"),
      reason: @form_field
    },
    %{file: "live/risk/policy_rule_dialog.ex", match: ~s(class="form-grid"), reason: @form_field},
    %{
      file: "live/transaction_management_live.ex",
      match: ~s(class="form-grid"),
      reason: @form_field
    },
    %{
      file: "live/securities_live.ex",
      match: ~s(class="research-entry-form__grid"),
      reason: @form_field
    },
    %{
      file: "live/securities/stories_tab.ex",
      match: ~s(class="research-entry-form__grid"),
      reason: @form_field
    },
    %{
      file: "live/securities/security_form_dialog.ex",
      match: ~s(<select name={"security["),
      reason: @form_field
    },
    %{file: "live/securities/filter_popover.ex", match: ~s(class="popover"), reason: @form_field},
    %{
      file: "live/classifications_live.ex",
      match: ~s(class="inline-form category-form"),
      reason: @form_field
    },
    %{
      file: "live/classifications_live.ex",
      match: ~s(class="cat-edit-form"),
      reason: @form_field
    },
    %{file: "live/snapshots_live.ex", match: ~s(id="snapshot-create-form"), reason: @form_field},
    %{
      file: "live/transaction_management_live.ex",
      match: ~s(class="transaction-filters"),
      reason:
        @form_field <>
          " (the history's „More filters“ in its disclosure: a select among two dates and a search)"
    },
    # One labelled select on its own line.
    %{
      file: "live/classifications_live.ex",
      match: ~s(id="soll-plan-picker-form"),
      reason: @single
    },
    %{file: "live/classifications_live.ex", match: ~s(id="soll-copy-form), reason: @single},
    %{
      file: "live/portfolio_accounts_live.ex",
      match: ~s(id={"liquidity-role-form-),
      reason: @single
    },
    # Sprint 29 C6 (board 02 ④), integrated with L4: the crash benchmark
    # chosen in place, in the crash windows' disclosure.
    %{
      file: "live/risk/crash_section.ex",
      match: ~s(id="crash-benchmark-form"),
      reason:
        @single <>
          " (the crash benchmark's form in the crash windows' disclosure: the select, then " <>
          "„Speichern“ and „Abbrechen“ and its notes under it)"
    }
  ]

  # User story (Sprint 29 L4):
  # As the owner who reviews decisions, not diffs,
  # I want no bar of labelled controls built beside the one component,
  # so that "labelled controls start on one edge" holds on every page, the
  # ones no walk reaches included, and a new bar cannot start a second
  # layout.
  #
  # Acceptance criteria:
  # - No select, segmented control or chip family with a visible label
  #   stands outside `ControlBar.bar` in lib/portfolixir_web/, unless an
  #   exception names it with its reason.
  # - The bars the inventory found without a visible label (`income_live.ex`,
  #   `portfolio_live.ex`'s performance and allocation bars, `tax_live.ex`,
  #   Prognosen' status) are registered with that reason, and each still has
  #   no visible label.
  # - Every exception carries a reason and matches at least one family of
  #   its kind; one that matches none fails as stale.
  test "no labelled select, segmented control or chip family stands outside the control bar" do
    families = scan_web()
    assert length(families) > 30, "the scan found only #{length(families)} control families"
    assert Enum.any?(families, & &1.in_bar), "the scan found no family inside ControlBar.bar"

    assert problems(families, @exceptions) == []
  end

  # The check's own attack (Sprint 29 plan, the attack lens of Lane L).
  #
  # Acceptance criteria:
  # - A labelled select outside the component is caught, by `for` and by a
  #   label around it; the same select inside `ControlBar.bar` is not.
  # - A label split across two elements before a chip family or a select,
  #   linked to nothing, is caught.
  # - A chip family named by `filter-chips__family`, and one named through
  #   `aria-labelledby`, are caught; one with only an `aria-label` is not.
  # - An exception without a reason is caught, and so is one that matches
  #   nothing; one registered as without a visible label is caught once
  #   its family gains one.
  # - The journal as it was before L2 (6177b94, its chips and its form) is
  #   caught.
  test "the check catches a labelled select, a split label and an exception without a reason" do
    outside = ~S"""
    <div class="toolbar">
      <label for="k">Kind</label>
      <select id="k" name="kind"><option>All</option></select>
    </div>
    """

    assert [%{kind: :select, labelled: true}] = scan_source("probe.ex", heex(outside))

    wrapped = ~S"""
    <label class="filter">
      <span><%= gettext("Kind") %></span>
      <select name="kind"><option>All</option></select>
    </label>
    """

    assert [%{labelled: true}] = scan_source("probe.ex", heex(wrapped))

    inside = ~S"""
    <ControlBar.bar>
      <:group label="Kind" for="k"><select id="k" name="kind"></select></:group>
    </ControlBar.bar>
    """

    assert [%{labelled: true, in_bar: true}] = families = scan_source("probe.ex", heex(inside))
    assert problems(families, []) == []

    split = ~S"""
    <div class="toolbar">
      <span class="muted">Deviating</span><span class="muted">by</span>
      <span class="filter-chips" role="group"><button class="filter-chip">1 pp</button></span>
      <strong>Sort</strong> <em>by</em>
      <select name="sort"><option>Name</option></select>
    </div>
    """

    assert [%{kind: :chips, labelled: true}, %{kind: :select, labelled: true}] =
             scan_source("probe.ex", heex(split))

    named = ~S"""
    <span class="filter-chips__group" role="group">
      <span class="filter-chips__family">Account</span>
      <button class="filter-chip">Giro</button>
    </span>
    <span id="type-label">Type</span>
    <span class="filter-chips" aria-labelledby="type-label"><button class="filter-chip">Buy</button></span>
    <span class="visually-hidden" id="hidden-label">Year</span>
    <nav class="segmented-control" aria-labelledby="hidden-label"><a>2026</a></nav>
    <nav class="segmented-control" aria-label="Taxpayer"><a>Family</a></nav>
    """

    assert [
             %{kind: :chips, labelled: true},
             %{kind: :chips, labelled: true},
             %{kind: :segmented, labelled: false},
             %{kind: :segmented, labelled: false}
           ] = scan_source("probe.ex", heex(named))

    families = scan_source("probe.ex", heex(outside))
    assert [problem] = problems(families, [])
    assert problem =~ "probe.ex:5: a labelled select outside ControlBar.bar"

    excused = [%{file: "probe.ex", match: ~s(class="toolbar"), reason: "a probe"}]
    assert problems(families, excused) == []

    assert [no_reason] =
             problems(families, [%{file: "probe.ex", match: ~s(class="toolbar"), reason: " "}])

    assert no_reason =~ "has no reason"

    assert [stale | _] =
             problems(families, excused ++ [%{file: "probe.ex", match: "nowhere", reason: "x"}])

    assert stale =~ "is stale"

    unlabelled = [%{file: "probe.ex", match: ~s(class="toolbar"), labelled: false, reason: "x"}]
    assert [gained, still_outside] = problems(families, unlabelled)

    assert gained =~
             "probe.ex:5: the select registered as without a visible label has a visible label now"

    assert still_outside =~ "probe.ex:5: a labelled select outside ControlBar.bar"

    # The journal's chips and its form before L2 (6177b94), trimmed to
    # their markup: the chips named their families in the row; the kind's
    # label was hidden, so its select is no labelled control.
    journal = ~S"""
    <div id="journal-chips" class="filter-chips" role="group" aria-label={gettext("Filter the journal")}>
      <span>
        <span class="filter-chips__family"><%= gettext("Actor") %></span>
        <button type="button" id="journal-chip-actor-all" class="filter-chip"><%= gettext("All") %></button>
      </span>
      <span>
        <span class="filter-chips__family"><%= gettext("Operation") %></span>
        <button :for={operation <- Entry.operations()} type="button" class="filter-chip">
          <%= Row.operation_label(operation) %>
        </button>
      </span>
    </div>
    <form id="journal-filters" class="journal-filters" phx-change="filter_form" phx-submit="filter_form">
      <label class="journal-filters__kind">
        <span class="visually-hidden"><%= gettext("Kind") %></span>
        <select id="journal-kind" name="resource_type">
          <option value=""><%= gettext("All kinds") %></option>
        </select>
      </label>
      <label class="journal-filters__since">
        <%= gettext("Since") %>
        <input type="text" id="journal-since" name="since" />
      </label>
    </form>
    """

    assert [%{kind: :chips, labelled: true, line: 3}, %{kind: :select, labelled: false}] =
             scan_source("journal_live.ex", heex(journal))

    assert [journal_problem] = problems(scan_source("journal_live.ex", heex(journal)), [])
    assert journal_problem =~ "journal_live.ex:3: a labelled chips outside ControlBar.bar"
  end

  # `body` as the one template of a source file.
  defp heex(body) do
    quotes = String.duplicate(~s("), 3)

    "  def render(assigns) do\n    ~H" <>
      quotes <> "\n" <> body <> "    " <> quotes <> "\n  end\n"
  end

  # --- the check ---

  defp problems(families, exceptions) do
    exception_problems =
      Enum.flat_map(exceptions, fn exception ->
        reason = Map.get(exception, :reason)
        unlabelled? = Map.get(exception, :labelled) == false
        matched = Enum.filter(families, &matches?(&1, exception))

        cond do
          not is_binary(reason) or String.trim(reason) == "" ->
            ["the exception #{inspect(exception.match)} in #{exception.file} has no reason"]

          unlabelled? and matched == [] ->
            [
              "the exception #{inspect(exception.match)} in #{exception.file} is stale: it matches no family"
            ]

          unlabelled? ->
            for %{labelled: true} = family <- matched do
              "#{where(family)}: the #{family.kind} registered as without a visible label " <>
                "has a visible label now (#{family.label}); move it onto ControlBar.bar"
            end

          not Enum.any?(matched, &(&1.labelled and not &1.in_bar)) ->
            [
              "the exception #{inspect(exception.match)} in #{exception.file} is stale: " <>
                "it matches no labelled family outside ControlBar.bar"
            ]

          true ->
            []
        end
      end)

    excused = Enum.filter(exceptions, &(Map.get(&1, :labelled) != false))

    violations =
      for family <- families,
          family.labelled and not family.in_bar,
          not Enum.any?(excused, &matches?(family, &1)) do
        "#{where(family)}: a labelled #{family.kind} outside ControlBar.bar (#{family.label}); " <>
          "build it as a group of PortfolixirWeb.ControlBar.bar/1, or register an exception " <>
          "with its reason in #{__ENV__.file}"
      end

    exception_problems ++ violations
  end

  defp matches?(family, %{file: file, match: match}) do
    family.file == file and Enum.any?(family.tags, &String.contains?(&1, match))
  end

  defp where(family), do: "#{family.file}:#{family.line}"

  defp scan_web do
    @web_glob
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      scan_source(Path.relative_to(path, "lib/portfolixir_web"), File.read!(path))
    end)
  end

  # Every control family of every `~H` template in `source`, each with its
  # kind, its line, whether a visible label belongs to it (and which), and
  # whether it stands inside `ControlBar.bar`.
  defp scan_source(file, source) do
    for {line, body} <- templates(source),
        nodes = parse(body, line),
        node <- Map.values(nodes),
        kind = kind(node, nodes),
        kind != nil do
      label = label(node, nodes) || own_name(node, nodes)

      %{
        file: file,
        line: node.line,
        kind: kind,
        labelled: label != nil,
        label: label,
        in_bar: Enum.any?(ancestors(node, nodes), &(&1.tag == "ControlBar.bar")),
        tags: [node.raw | Enum.map(ancestors(node, nodes), & &1.raw)]
      }
    end
    |> Enum.sort_by(& &1.line)
  end

  # The `~H"""` heredocs and the one-line `~H"..."` sigils, each with the
  # line its body starts on.
  defp templates(source) do
    heredocs =
      ~r/~H"""\n(.*?)\n[ \t]*"""/s
      |> Regex.scan(source, return: :index)
      |> Enum.map(fn [_, {start, length}] -> {start, binary_part(source, start, length)} end)

    inline =
      ~r/~H"((?:[^"\\\n]|\\.)+)"/
      |> Regex.scan(source, return: :index)
      |> Enum.map(fn [_, {start, length}] -> {start, binary_part(source, start, length)} end)

    for {start, body} <- heredocs ++ inline do
      {line_at(source, start), body}
    end
  end

  defp line_at(source, offset) do
    source |> binary_part(0, offset) |> String.split("\n") |> length()
  end

  defp kind(%{tag: "select"}), do: :select

  defp kind(%{tag: "ChangedSince.chips", attrs: attrs}) do
    if Map.has_key?(attrs, "label_id"), do: nil, else: :chips
  end

  defp kind(node) do
    classes = classes(node)

    cond do
      "segmented-control" in classes -> :segmented
      "filter-chips" in classes or "filter-chips__group" in classes -> :chips
      true -> nil
    end
  end

  # A family's name (`filter-chips__family`) outside any family the reader
  # found: its chips come from a function component, so the name stands for
  # the family.
  defp kind(node, nodes) do
    case kind(node) do
      nil ->
        if "filter-chips__family" in classes(node) and
             not Enum.any?(ancestors(node, nodes), &(kind(&1) != nil)),
           do: :chips

      kind ->
        kind
    end
  end

  # The visible label that belongs to a family, by the five ways above, or nil.
  defp label(node, nodes) do
    by_group(node, nodes) || by_id(node, nodes) || by_for(node, nodes) ||
      by_wrapper(node, nodes) || by_family_name(node, nodes) || by_place(node, nodes) ||
      by_component(node)
  end

  # Inside the component, a group's `label` is the family's.
  defp by_group(node, nodes) do
    case Enum.find(ancestors(node, nodes), &(&1.tag == ":group" and is_binary(&1.attrs["label"]))) do
      nil -> nil
      group -> "the bar's group " <> group.attrs["label"]
    end
  end

  defp by_id(node, nodes) do
    with value when is_binary(value) <- node.attrs["aria-labelledby"],
         %{} = target <- Enum.find(Map.values(nodes), &(&1.attrs["id"] == value)),
         false <- hidden?(target, nodes) do
      "aria-labelledby " <> text_of(target, nodes)
    else
      _ -> nil
    end
  end

  defp by_for(%{tag: "select"} = node, nodes) do
    with value when is_binary(value) <- node.attrs["id"],
         %{} = target <-
           Enum.find(Map.values(nodes), &(&1.tag == "label" and &1.attrs["for"] == value)),
         false <- hidden?(target, nodes) do
      "<label for> " <> text_of(target, nodes)
    else
      _ -> nil
    end
  end

  defp by_for(_node, _nodes), do: nil

  defp by_wrapper(node, nodes) do
    case Enum.find(ancestors(node, nodes), &(&1.tag == "label")) do
      nil ->
        nil

      wrapper ->
        text = text_of(wrapper, nodes, except: node.id)
        if not hidden?(wrapper, nodes) and text != "", do: "<label> around it " <> text
    end
  end

  defp by_family_name(node, nodes) do
    case Enum.find(descendants(node, nodes), &("filter-chips__family" in classes(&1))) do
      nil -> nil
      name -> if hidden?(name, nodes), do: nil, else: "family name " <> text_of(name, nodes)
    end
  end

  # A label beside the family, linked to nothing: what stands right before
  # it (nothing but space between) is text, or an element that carries
  # visible text and is no control (a span, a strong, ...; never a button
  # or a link).
  defp by_place(node, nodes) do
    case previous_sibling(node, nodes) do
      {:text, text} ->
        if String.match?(text, ~r/\p{L}|<%/u), do: "the text before it " <> text

      %{tag: tag} = before when tag in ~w(div p) or tag in @label_tags ->
        text = text_of(before, nodes)

        label? =
          (tag in @label_tags or Enum.any?(classes(before), &String.contains?(&1, "label"))) and
            not hidden?(before, nodes) and not control?(before, nodes) and text != ""

        if label?, do: "the element before it " <> text

      _ ->
        nil
    end
  end

  # A family's name standing for its family is its label.
  defp own_name(node, nodes) do
    if "filter-chips__family" in classes(node) and not hidden?(node, nodes),
      do: "family name " <> text_of(node, nodes)
  end

  # `ChangedSince.chips` without a bar's label id names its own family.
  defp by_component(%{tag: "ChangedSince.chips"}), do: "its own name „Changed since“"
  defp by_component(_node), do: nil

  defp hidden?(node, nodes) do
    Enum.any?(
      [node | ancestors(node, nodes)],
      &Enum.any?(classes(&1), fn c -> c in @hidden_classes end)
    )
  end

  # An element that is, or holds, a control or a family.
  defp control?(node, nodes) do
    Enum.any?([node | descendants(node, nodes)], &(&1.tag in @control_tags or kind(&1) != nil))
  end

  defp classes(node) do
    case node.attrs["class"] do
      nil -> []
      value -> ~r/[\w-]+/ |> Regex.scan(value) |> List.flatten()
    end
  end

  # The text a node shows: its own text and its descendants', those inside
  # a visually hidden element or inside `except` left out. An expression
  # (`<%= ... %>`) counts as text.
  defp text_of(node, nodes, opts \\ []) do
    except = Keyword.get(opts, :except)

    if Enum.any?(classes(node), &(&1 in @hidden_classes)) or node.id == except do
      ""
    else
      node.children
      |> Enum.map(fn
        {:text, text} -> text
        {:node, id} -> text_of(nodes[id], nodes, opts)
      end)
      |> Enum.join(" ")
      |> String.replace(~r/\s+/, " ")
      |> String.trim()
    end
  end

  defp ancestors(%{parent: nil}, _nodes), do: []
  defp ancestors(%{parent: 0}, _nodes), do: []
  defp ancestors(%{parent: parent}, nodes), do: [nodes[parent] | ancestors(nodes[parent], nodes)]

  defp descendants(node, nodes) do
    Enum.flat_map(node.children, fn
      {:node, id} -> [nodes[id] | descendants(nodes[id], nodes)]
      _text -> []
    end)
  end

  # The element right before `node` in its parent, if only space (or an
  # EEx control line) stands between them.
  defp previous_sibling(node, nodes) do
    nodes[node.parent].children
    |> Enum.take_while(&(&1 != {:node, node.id}))
    |> Enum.reverse()
    |> Enum.drop_while(fn
      {:text, text} -> String.trim(text) == ""
      _ -> false
    end)
    |> case do
      [{:node, id} | _] -> nodes[id]
      [{:text, text} | _] -> {:text, String.trim(text)}
      [] -> nil
    end
  end

  # --- a small HEEx reader: tags, their attributes, text and nesting ---

  # Parses a template into %{id => node}; a node is %{id, tag, attrs, raw,
  # line, parent, children}, children as {:node, id} and {:text, text}.
  defp parse(body, first_line) do
    root = %{id: 0, tag: :root, attrs: %{}, raw: "", line: first_line, parent: nil, children: []}

    {nodes, _stack} =
      body
      |> tokens(first_line)
      |> Enum.reduce({%{0 => root}, [0]}, fn token, {nodes, [top | _] = stack} ->
        case token do
          {:text, text} ->
            {update_in(nodes[top].children, &(&1 ++ [{:text, text}])), stack}

          {:close, tag} ->
            {nodes, close(stack, nodes, tag)}

          {:open, tag, raw, line, self_closing} ->
            id = map_size(nodes)

            node = %{
              id: id,
              tag: tag,
              attrs: attrs(raw),
              raw: raw,
              line: line,
              parent: top,
              children: []
            }

            nodes =
              nodes |> Map.put(id, node) |> update_in([top, :children], &(&1 ++ [{:node, id}]))

            if self_closing or tag in @void, do: {nodes, stack}, else: {nodes, [id | stack]}
        end
      end)

    nodes
  end

  defp close(stack, nodes, tag) do
    case Enum.find_index(stack, &(&1 != 0 and nodes[&1].tag == tag)) do
      nil -> stack
      index -> Enum.drop(stack, index + 1)
    end
  end

  defp tokens(body, line), do: tokens(body, line, [])

  defp tokens("", _line, acc), do: Enum.reverse(acc)

  defp tokens("<%!--" <> rest, line, acc), do: skip_to(rest, "--%>", line, acc)
  defp tokens("<!--" <> rest, line, acc), do: skip_to(rest, "-->", line, acc)

  defp tokens("<%" <> rest, line, acc) do
    [code, rest] = String.split(rest, "%>", parts: 2)
    line = line + count_lines(code)
    # An expression's output counts as text; a block's `do`/`end` does not.
    output? = String.starts_with?(code, "=") and not Regex.match?(~r/\b(do|->)\s*$/, code)
    tokens(rest, line, if(output?, do: [{:text, "<%#{code}%>"} | acc], else: acc))
  end

  defp tokens("</" <> rest, line, acc) do
    [tag, rest] = String.split(rest, ">", parts: 2)
    tokens(rest, line + count_lines(tag), [{:close, String.trim(tag)} | acc])
  end

  defp tokens("<" <> rest, line, acc) do
    case Regex.run(~r/^[A-Za-z.:][\w.:-]*/, rest) do
      [tag] ->
        {raw, rest} =
          tag_body(binary_part(rest, byte_size(tag), byte_size(rest) - byte_size(tag)), "")

        self_closing = String.ends_with?(raw, "/")
        token = {:open, tag, "<" <> tag <> raw <> ">", line, self_closing}
        tokens(rest, line + count_lines(raw), [token | acc])

      nil ->
        tokens(rest, line, [{:text, "<"} | acc])
    end
  end

  defp tokens(body, line, acc) do
    [text | _] = String.split(body, "<", parts: 2)
    rest = binary_part(body, byte_size(text), byte_size(body) - byte_size(text))
    tokens(rest, line + count_lines(text), [{:text, text} | acc])
  end

  defp skip_to(rest, marker, line, acc) do
    [skipped, rest] = String.split(rest, marker, parts: 2)
    tokens(rest, line + count_lines(skipped), acc)
  end

  # A tag's attributes up to its `>`, past quotes and `{...}` expressions
  # (which may hold a `>`).
  defp tag_body(">" <> rest, raw), do: {raw, rest}
  defp tag_body("", raw), do: {raw, ""}

  defp tag_body("\"" <> rest, raw) do
    [quoted, rest] = String.split(rest, "\"", parts: 2)
    tag_body(rest, raw <> "\"" <> quoted <> "\"")
  end

  defp tag_body("{" <> rest, raw) do
    {expression, rest} = braces(rest, 1, "{")
    tag_body(rest, raw <> expression)
  end

  defp tag_body(<<char::utf8, rest::binary>>, raw), do: tag_body(rest, raw <> <<char::utf8>>)

  defp braces(rest, 0, acc), do: {acc, rest}
  defp braces("", _depth, acc), do: {acc, ""}
  defp braces("{" <> rest, depth, acc), do: braces(rest, depth + 1, acc <> "{")
  defp braces("}" <> rest, depth, acc), do: braces(rest, depth - 1, acc <> "}")

  defp braces("\"" <> rest, depth, acc) do
    {string, rest} = string_body(rest, "")
    braces(rest, depth, acc <> "\"" <> string <> "\"")
  end

  defp braces(<<char::utf8, rest::binary>>, depth, acc),
    do: braces(rest, depth, acc <> <<char::utf8>>)

  # An Elixir string inside an expression, past escapes; `#{...}` inside it
  # holds no quote this reader needs to see.
  defp string_body("\\" <> <<char::utf8, rest::binary>>, acc),
    do: string_body(rest, acc <> "\\" <> <<char::utf8>>)

  defp string_body("\"" <> rest, acc), do: {acc, rest}
  defp string_body("", acc), do: {acc, ""}

  defp string_body(<<char::utf8, rest::binary>>, acc),
    do: string_body(rest, acc <> <<char::utf8>>)

  # name="value", name={expression} and a bare name, read left to right
  # past expressions; a value is compared as written.
  defp attrs(raw) do
    raw
    |> String.replace(~r/^<[^\s>\/]+/, "")
    |> read_attrs(%{})
  end

  defp read_attrs(rest, acc) do
    rest = String.trim_leading(rest)

    case Regex.run(~r/^([^\s=\/>{"]+)(=?)/, rest) do
      [whole, name, "="] ->
        value_and_rest = binary_part(rest, byte_size(whole), byte_size(rest) - byte_size(whole))
        {value, rest} = attr_value(value_and_rest)
        read_attrs(rest, Map.put(acc, name, value))

      [whole, name, ""] ->
        read_attrs(
          binary_part(rest, byte_size(whole), byte_size(rest) - byte_size(whole)),
          Map.put(acc, name, true)
        )

      nil ->
        case rest do
          "{" <> more -> more |> braces(1, "{") |> elem(1) |> read_attrs(acc)
          "" -> acc
          <<_::utf8, more::binary>> -> read_attrs(more, acc)
        end
    end
  end

  defp attr_value("\"" <> rest) do
    [value, rest] = String.split(rest, "\"", parts: 2)
    {value, rest}
  end

  defp attr_value("{" <> rest), do: braces(rest, 1, "{")
  defp attr_value(rest), do: {"", rest}

  defp count_lines(text), do: text |> String.graphemes() |> Enum.count(&(&1 == "\n"))
end
