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

  # The `render_cell/2` clauses of `source`, each as `{line, raw_calls}`:
  # the lines of its `raw/1` or `Phoenix.HTML.raw/1` calls.
  defp render_cell_raw_calls(source) do
    {:ok, ast} = Code.string_to_quoted(source, columns: true)

    {_ast, clauses} =
      Macro.prewalk(ast, [], fn
        {:defp, meta, [head | _body]} = node, acc ->
          if render_cell_head?(head),
            do: {node, [{meta[:line], raw_calls(node)} | acc]},
            else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(clauses)
  end

  defp render_cell_head?({:when, _meta, [head | _guards]}), do: render_cell_head?(head)
  defp render_cell_head?({:render_cell, _meta, args}) when is_list(args), do: true
  defp render_cell_head?(_head), do: false

  defp raw_calls(clause) do
    {_ast, lines} =
      Macro.prewalk(clause, [], fn
        {{:., _dot, [{:__aliases__, _alias, [:Phoenix, :HTML]}, :raw]}, meta, [_arg]} = node,
        acc ->
          {node, [meta[:line] | acc]}

        {:raw, meta, [_arg]} = node, acc ->
          {node, [meta[:line] | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(lines)
  end

  # User story (#1365, the "render_cell raw/1" line):
  # As the owner who does not read the code,
  # I want no securities cell built by `raw/1`,
  # so that the escaping of a stored value cannot be forgotten in a string
  # and the Sobelow gate can move to 0.18 without a skip.
  #
  # Acceptance criteria:
  # - No `render_cell/2` clause of `securities_live.ex` calls `raw/1` or
  #   `Phoenix.HTML.raw/1`.
  # - The scan finds the clauses (it is not vacuous), and it flags both
  #   spellings of the call in a clause written to break the rule.
  test "no render_cell/2 clause calls raw/1" do
    clauses = @source |> File.read!() |> render_cell_raw_calls()

    assert length(clauses) >= 10, "expected the render_cell/2 clauses, found #{length(clauses)}"
    assert Enum.filter(clauses, fn {_line, calls} -> calls != [] end) == []

    attack = """
    defmodule Attack do
      defp render_cell(%{render_hint: :badge}, value) do
        Phoenix.HTML.raw("<span>" <> value <> "</span>")
      end

      defp render_cell(field, value) when is_map(field), do: raw(value)

      defp render_cell(_field, value) do
        assigns = %{value: value}
        ~H"<code>{@value}</code>"
      end

      defp other(value), do: raw(value)
    end
    """

    assert render_cell_raw_calls(attack) == [{2, [3]}, {6, [6]}, {8, []}]
  end
end
