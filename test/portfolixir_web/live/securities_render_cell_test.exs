defmodule PortfolixirWeb.SecuritiesRenderCellTest do
  # Sprint 26 M1 (#1365, the Securities polish list's "render_cell raw/1"
  # line): the securities table's badge, code, signed-money and
  # signed-percent cells were built as strings and handed to `raw/1`.
  # Sobelow 0.18 flags each such call (`XSS.Raw`), so the clauses move to
  # HEEx, which escapes by construction. The move must not change a cell:
  # the first test pins every clause's markup for representative values
  # (nil, positive, negative, a figure that rounds to zero, a stale close,
  # and stored values carrying HTML-special characters); the second keeps
  # `raw/1` out of `render_cell/2`. Every name and figure is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures, only: [create_security!: 1, put_quotes!: 2]

  import Ecto.Query, only: [from: 2]

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.AssetClasses
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Repo

  @source Path.expand("../../../lib/portfolixir_web/live/securities_live.ex", __DIR__)

  @columns ~w(name provider feed latest_feed day_change_abs day_change_pct performance_1m performance_1y)

  # A stored value outside the closed provider and feed sets — written past
  # the changeset, as an import or an older release could have left it. The
  # journal actor setting lets the armed table accept the raw write (the
  # mechanism `Portfolixir.Journal.record/3` uses).
  defp store_raw!(security, fields) do
    {:ok, {1, _}} =
      Repo.transaction(fn ->
        Repo.query!("SELECT set_config('portfolixir.journal_actor', 'test_raw_cell', true)")
        Repo.update_all(from(s in Security, where: s.id == ^security.id), set: fields)
      end)

    security
  end

  defp day(offset), do: Date.add(Portfolixir.Clock.today(), offset)

  # The cells of one table row after the kebab and the name, each as its
  # inner markup, in column order.
  defp cells(html, security) do
    html
    |> Floki.parse_document!()
    |> Floki.find("#security-row-#{security.id} > td")
    |> Enum.drop(2)
    |> Enum.map(fn {"td", _attrs, children} -> children |> Floki.raw_html() |> String.trim() end)
  end

  defp phone_change(html, security) do
    html
    |> Floki.parse_document!()
    |> Floki.find("#security-phone-#{security.id} .phone-row__figure2")
    |> Floki.raw_html()
  end

  # User story (#1365, the "render_cell raw/1" line):
  # As the operator reading the securities list with the provider, feed and
  # change columns shown,
  # I want every cell to read exactly as before the cells moved to HEEx,
  # so that a security hardening changes no figure, colour or label on the
  # screen.
  #
  # Acceptance criteria:
  # - A provider reads as a `.badge`, a feed as `<code>`, an absent value as
  #   an empty cell.
  # - The day change reads signed with two places in `decimal-positive`,
  #   `decimal-negative` or `decimal-neutral` (a figure rounding to 0.00);
  #   the percents read signed with one place and `%`, in
  #   `decimal-positive`, `decimal-negative` or `is-flat`.
  # - A change computed from a stale close reads "—".
  # - A stored provider or feed carrying `<`, `>`, `&`, `"` or `'` reads as
  #   text: no element is injected.
  # - The phone row's day change carries the same span as the table cell.
  test "the badge, code and signed cells keep their markup", %{conn: conn} do
    rise = create_security!(name: "Synthetic Cell Rise", ticker: "SCR")
    store_raw!(rise, provider: "coingecko", feed: "COINGECKO", latest_feed: "MANUAL")

    put_quotes!(rise, [
      {day(-400), "50"},
      {day(-40), "80"},
      {day(-1), "100.00"},
      {day(0), "102.50"}
    ])

    fall = create_security!(name: "Synthetic Cell Fall", ticker: "SCF")
    put_quotes!(fall, [{day(-1), "100"}, {day(0), "97.25"}])

    flat = create_security!(name: "Synthetic Cell Flat", ticker: "SCL")
    put_quotes!(flat, [{day(-1), "100"}, {day(0), "100.004"}])

    bare = create_security!(name: "Synthetic Cell Bare", ticker: "SCB")

    stale = create_security!(name: "Synthetic Cell Stale", ticker: "SCS")
    put_quotes!(stale, [{day(-20), "100"}, {day(-19), "101"}])

    hostile = create_security!(name: "Synthetic Cell Hostile", ticker: "SCH")

    store_raw!(hostile,
      provider: ~s(<b class="x">P&'Q'</b>),
      feed: ~s{<script>alert("f")</script>},
      latest_feed: "a&b"
    )

    {:ok, view, _html} = live(conn, "/securities")
    html = render_hook(view, "set_columns", %{"columns" => @columns})

    assert cells(html, rise) == [
             ~s(<span class="badge">coingecko</span>),
             ~s(<code>CoinGecko</code>),
             ~s(<code>Manual</code>),
             ~s(<span class="decimal-positive">+2.50</span>),
             ~s(<span class="decimal-positive">+2.5%</span>),
             ~s(<span class="decimal-positive">+28.1%</span>),
             ~s(<span class="decimal-positive">+105.0%</span>)
           ]

    assert cells(html, fall) == [
             "",
             "",
             "",
             ~s(<span class="decimal-negative">-2.75</span>),
             ~s(<span class="decimal-negative">-2.8%</span>),
             "",
             ""
           ]

    assert cells(html, flat) == [
             "",
             "",
             "",
             ~s(<span class="decimal-neutral">0.00</span>),
             ~s(<span class="is-flat">0.0%</span>),
             "",
             ""
           ]

    assert cells(html, bare) == ["", "", "", "", "", "", ""]

    assert cells(html, stale) == ["", "", "", "—", "—", "", ""]

    assert cells(html, hostile) == [
             ~s(<span class="badge">&lt;b class=&quot;x&quot;&gt;P&amp;&#39;Q&#39;&lt;/b&gt;</span>),
             ~s{<code>&lt;script&gt;alert(&quot;f&quot;)&lt;/script&gt;</code>},
             ~s(<code>A&amp;b</code>),
             "",
             "",
             "",
             ""
           ]

    refute html =~ "<script>alert"
    refute html =~ ~s(<b class="x">)

    assert phone_change(html, rise) ==
             ~s(<span class="phone-row__figure2"><span class="decimal-positive">+2.5%</span></span>)

    assert phone_change(html, fall) ==
             ~s(<span class="phone-row__figure2"><span class="decimal-negative">-2.8%</span></span>)

    assert phone_change(html, bare) == ~s(<span class="phone-row__figure2">—</span>)
  end

  # The asset-class cell of a table row as the server sent it: the bytes
  # between the cell's `<td>` and `</td>`, less the row template's own
  # indentation around them. Nothing is parsed, so an attribute's order,
  # quoting and spelling count as much as the text does.
  defp raw_class_cell(page, security) do
    [row] = Regex.run(~r/<tr\s[^>]*id="security-row-#{security.id}".*?<\/tr>/s, page)

    [cell] =
      for [inner] <- Regex.scan(~r/<td[^>]*>(.*?)<\/td>/s, row, capture: :all_but_first),
          inner =~ "data-asset-class" or inner =~ "quick-assign-",
          do: String.trim(inner)

    cell
  end

  # The phone row's identifier line, which ends in the same cell: one line
  # of the page, taken whole.
  defp raw_phone_ids(page, security) do
    [_, line] =
      Regex.run(
        ~r/id="security-phone-#{security.id}".*?<span class="phone-row__ids">\s*([^\n]*)\n/s,
        page
      )

    line
  end

  # User story (R-148; #1365's "render_cell raw/1" line, finished):
  # As the operator reading the securities list,
  # I want the asset-class cell to read exactly as it did before it became a
  # template,
  # so that the hardening changes no badge, no marker and no control on the
  # screen, in the table or in the phone row.
  #
  # Acceptance criteria, on the page as the server sends it, byte for byte:
  # - A stated class is one `.badge` with `data-asset-class="stated"`.
  # - A derived class is the `.badge--derived` badge with its hidden
  #   "Derived: " text and its marker, followed at once by the quick-assign
  #   form.
  # - A security with neither is the quick-assign form alone.
  # - The form carries its id (`quick-assign-<id>` in the table,
  #   `phone-quick-assign-<id>` in the phone row), its event, the security's
  #   id, `data-swallow-click`, and one option per asset class after the
  #   empty one, in the order and with the attributes it always had.
  # - A stored class carrying `<`, `>`, `&`, `"` or `'` reads as text.
  test "the asset-class cell keeps its markup, byte for byte", %{conn: conn} do
    actor = Portfolixir.Actor.owner_ui()

    {:ok, stated} =
      Catalog.create_security(actor, %{
        name: "Synthetic Class Stated",
        ticker_symbol: "SYS",
        isin: "DE000SYNTHS1",
        currency_code: "EUR",
        asset_class: "equity"
      })

    # No class stored and none in the name; a resolved logo beside an ISIN
    # is what derives "equity" (Security.effective_asset_class/1).
    {:ok, derived} =
      Catalog.create_security(actor, %{
        name: "Synthetic Nordwind Beteiligungen",
        ticker_symbol: "SYD",
        isin: "DE000SYNTHD1",
        currency_code: "EUR"
      })

    {:ok, derived} =
      Catalog.put_logo_attributes(derived, %{"logo_path" => "/logos/synthetic.png"})

    assert is_nil(derived.asset_class) and Security.effective_asset_class(derived) == "equity"

    {:ok, blank} =
      Catalog.create_security(actor, %{
        name: "Synthetic Rohdaten Posten",
        ticker_symbol: "SYB",
        currency_code: "EUR"
      })

    assert is_nil(blank.asset_class) and is_nil(Security.effective_asset_class(blank))

    hostile = create_security!(name: "Synthetic Class Hostile", ticker: "SYH")
    store_raw!(hostile, asset_class: ~s(<b class="x">P&'Q'</b>))

    options =
      Enum.map_join(AssetClasses.options(), fn {label, code} ->
        ~s(<option value="#{code}">#{label}</option>)
      end)

    assert String.starts_with?(
             options,
             ~s(<option value="equity">Equity</option><option value="etf">ETF</option>)
           )

    form = fn prefix, security ->
      ~s(<form id="#{prefix}-#{security.id}" phx-change="quick_assign_asset_class" ) <>
        ~s(phx-value-id="#{security.id}" data-swallow-click class="quick-assign-form">) <>
        ~s(<select name="asset_class" class="quick-assign-select" ) <>
        ~s(aria-label="Assign asset class"><option value="">—</option>) <>
        options <> ~s(</select></form>)
    end

    stated_badge = ~s(<span class="badge" data-asset-class="stated">Equity</span>)

    derived_badge =
      ~s(<span class="badge badge--derived" data-asset-class="derived">) <>
        ~s(<span class="visually-hidden">Derived: </span>) <>
        ~s(<span class="badge-derived-marker" aria-hidden="true">≈</span>Equity</span>)

    hostile_badge =
      ~s(<span class="badge" data-asset-class="stated">) <>
        ~s(&lt;b class=&quot;x&quot;&gt;p&amp;&#39;q&#39;&lt;/b&gt;</span>)

    page = conn |> get("/securities") |> html_response(200)

    assert raw_class_cell(page, stated) == stated_badge
    assert raw_class_cell(page, derived) == derived_badge <> form.("quick-assign", derived)
    assert raw_class_cell(page, blank) == form.("quick-assign", blank)
    assert raw_class_cell(page, hostile) == hostile_badge

    assert raw_phone_ids(page, stated) == "SYS · DE000SYNTHS1 · " <> stated_badge

    assert raw_phone_ids(page, derived) ==
             "SYD · DE000SYNTHD1 · " <> derived_badge <> form.("phone-quick-assign", derived)

    assert raw_phone_ids(page, blank) == "SYB · " <> form.("phone-quick-assign", blank)
    assert String.ends_with?(raw_phone_ids(page, hostile), " · " <> hostile_badge)

    refute page =~ ~s(<b class="x">)
  end

  # Every function clause of `source` as `{name, line, raw_calls}`: the
  # lines on which it calls a function named `raw` -- `raw/1` as imported,
  # `Phoenix.HTML.raw/1` under whatever name the module goes by, piped into
  # or captured.
  defp function_raw_calls(source) do
    {:ok, ast} = Code.string_to_quoted(source, columns: true)

    {_ast, clauses} =
      Macro.prewalk(ast, [], fn
        {kind, meta, [head | _body]} = node, acc when kind in [:def, :defp] ->
          {node, [{function_name(head), meta[:line], raw_calls(node)} | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(clauses)
  end

  defp function_name({:when, _meta, [head | _guards]}), do: function_name(head)
  defp function_name({name, _meta, _args}) when is_atom(name), do: name

  defp raw_calls(clause) do
    {_ast, lines} =
      Macro.prewalk(clause, [], fn
        # `Phoenix.HTML.raw(x)` and `HTML.raw(x)`: a call, with its
        # parentheses. `since.raw`, a field read, has none and is no call.
        {{:., _dot, [_module, :raw]}, meta, args} = node, acc when is_list(args) ->
          if meta[:no_parens], do: {node, acc}, else: {node, [meta[:line] | acc]}

        # `raw(x)` as imported, and `x |> raw()`.
        {:raw, meta, args} = node, acc when is_list(args) ->
          {node, [meta[:line] | acc]}

        # `&raw/1` and `&Phoenix.HTML.raw/1`.
        {:&, meta, [{:/, _slash, [{:raw, _name, context}, _arity]}]} = node, acc
        when is_atom(context) ->
          {node, [meta[:line] | acc]}

        {:&, meta, [{:/, _slash, [{{:., _dot, [_module, :raw]}, _call, _args}, _arity]}]} = node,
        acc ->
          {node, [meta[:line] | acc]}

        node, acc ->
          {node, acc}
      end)

    lines |> Enum.reverse() |> Enum.uniq()
  end

  # User story (#1365, the "render_cell raw/1" line; R-148):
  # As the owner who does not read the code,
  # I want no securities cell built by `raw/1`,
  # so that the escaping of a stored value cannot be forgotten in a string
  # and the Sobelow gate holds without a skip.
  #
  # Acceptance criteria:
  # - No function of `securities_live.ex` calls `raw/1` or
  #   `Phoenix.HTML.raw/1`: not a `render_cell/2` clause, and not a helper a
  #   clause hands its cell to, as the asset-class cell's is.
  # - The file carries no `sobelow_skip` annotation for `XSS.Raw`.
  # - The scan finds the clauses and the asset-class cell's helper (it is
  #   not vacuous), and it flags every spelling of the call in a module
  #   written to break the rule, in a clause and in a helper.
  test "no function of the Securities page builds markup with raw/1" do
    source = File.read!(@source)
    functions = function_raw_calls(source)

    assert Enum.count(functions, &match?({:render_cell, _line, _calls}, &1)) >= 10
    assert Enum.any?(functions, &match?({:asset_class_cell, _line, _calls}, &1))

    assert Enum.filter(functions, fn {_name, _line, calls} -> calls != [] end) == []

    refute source =~ ~r/sobelow_skip\s*\[[^\]]*XSS\.Raw/,
           "a function of the Securities page is exempt from Sobelow's XSS.Raw"

    attack = """
    defmodule Attack do
      alias Phoenix.HTML

      defp render_cell(%{render_hint: :badge}, value) do
        Phoenix.HTML.raw("<span>" <> value <> "</span>")
      end

      defp render_cell(field, value) when is_map(field), do: raw(value)

      defp render_cell(_field, value) do
        assigns = %{value: value}
        ~H"<code>{@value}</code>"
      end

      defp other(value), do: raw(value)

      defp renamed(value), do: HTML.raw(value)

      defp piped(value) do
        value
        |> to_string()
        |> raw()
      end

      defp captured(values), do: Enum.map(values, &raw/1)

      def captured_remote(values), do: Enum.map(values, &Phoenix.HTML.raw/1)

      defp raw_material(raw), do: raw <> "a variable of that name is no call"
    end
    """

    assert function_raw_calls(attack) == [
             {:render_cell, 4, [5]},
             {:render_cell, 8, [8]},
             {:render_cell, 10, []},
             {:other, 15, [15]},
             {:renamed, 17, [17]},
             {:piped, 19, [22]},
             {:captured, 25, [25]},
             {:captured_remote, 27, [27]},
             {:raw_material, 29, []}
           ]
  end
end
