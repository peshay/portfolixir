defmodule Portfolixir.Invariants.DisplayedDatesTest do
  # Sprint 19 PR γ U3 (issues 1061, 1087, 1088; board
  # ux-design-2026-10-04/05-dates-charts): UX-DR19 as amended on 2026-10-03
  # says a date the page only shows follows the page's language through
  # `Format.date`, and ISO stays where a date is entered or exchanged. The
  # issues listed the screens a reader found; the board found as many again
  # that no issue named. This meta-test keeps the sweep swept: it scans the
  # web layer's source, AST-based, so a mention in a comment or a doc string
  # never counts.
  use ExUnit.Case, async: true

  # The API is the exchange format: its JSON keeps ISO by contract.
  @excluded_dirs ["lib/portfolixir_web/controllers/api/"]

  # In a HEEx template, an ISO date inside one of these attributes is a value
  # a machine reads, not text a reader sees.
  @machine_attributes ~w(datetime value href navigate patch)
  @machine_attribute_prefixes ~w(phx-value- data-)

  # Outside a template, the functions that build an ISO date for a machine,
  # each with its reason. Every entry must still make the call, so the list
  # never outlives its reason.
  @allowed %{
    {"lib/portfolixir_web/format.ex", :date} =>
      "the English form of a displayed date is ISO (UX-DR19)",
    {"lib/portfolixir_web/components/security_chart.ex", :payload_date} =>
      "the crosshair hook's JSON: the zoom sends the dates back as the custom range",
    {"lib/portfolixir_web/components/changed_since.ex", :since_value} =>
      "the since= URL value, the API's own parameter",
    {"lib/portfolixir_web/live/risk/policy_rule_dialog.ex", :valid_from_value} =>
      "the rule dialog's \"In force from\" input value",
    {"lib/portfolixir_web/live/securities/security_form_dialog.ex", :date_value} =>
      "the bond section's date input values",
    {"lib/portfolixir_web/live/securities/merge_dialog.ex", :isin_change_default} =>
      "the ISIN-change date input's default",
    {"lib/portfolixir_web/live/securities/quote_release_dialog.ex", :iso} =>
      "the release range's input values and its chips' phx-values",
    {"lib/portfolixir_web/live/securities/manual_quotes.ex", :datetime_value} =>
      "the datetime attribute of the note's <time>, built as safe markup",
    {"lib/portfolixir_web/live/securities_live.ex", :research_today_value} =>
      "the research entry's as-of input default",
    {"lib/portfolixir_web/live/transaction_management_live.ex", :date_field_value} =>
      "the booking drawer's date input and the notes drawer's disabled one"
  }

  # User story:
  # As a German-speaking operator,
  # I want every date the app only shows me to read DD.MM.YYYY,
  # so that a screen nobody listed does not slip back to ISO beside the
  # screens a sweep fixed.
  #
  # Acceptance criteria:
  # - No template in lib/portfolixir_web renders `Date.to_iso8601`,
  #   `DateTime.to_iso8601`, `NaiveDateTime.to_iso8601`, `Date.to_string` or
  #   a `Calendar.strftime` with an ISO date format, except inside a
  #   `datetime`, `value`, `href`, `navigate`, `patch`, `phx-value-*` or
  #   `data-*` attribute.
  # - No function outside a template makes one of those calls unless it is
  #   on the allow-list with its reason; the API directory is out of scope.
  # - Every allow-list entry still makes the call.
  test "no template or LiveView renders an ISO date outside the allow-list" do
    calls = for path <- sources(), call <- iso_calls(File.read!(path)), do: {path, call}

    offenders =
      for {path, call} <- calls, offender?(path, call) do
        "#{path}:#{call.line} — #{call.what}#{where(call)}"
      end

    assert offenders == [], """
    A displayed date goes through PortfolixirWeb.Format.date/2 (DD.MM.YYYY in
    German, ISO in English; UX-DR19, Sprint 19 U3). ISO is for a date a machine
    reads: put it in a `datetime`, `value`, `phx-value-*` or `data-*`
    attribute, or add the function to the allow-list here with its reason.
    #{Enum.join(offenders, "\n")}
    """

    for {{path, function}, _reason} <- @allowed do
      assert Enum.any?(calls, fn {p, call} ->
               p == path and call.context == {:code, function}
             end),
             "#{path} #{function} no longer builds an ISO date; remove it from the allow-list"
    end
  end

  test "the scan flags a displayed ISO date and passes a machine's" do
    flagged = fn source -> source |> iso_calls() |> Enum.reject(&machine?/1) end

    assert [%{line: 2, context: {:template, :text}}] =
             flagged.(
               ~s|defmodule A do\n  def r(assigns), do: ~H"<td><%= Date.to_iso8601(@d) %></td>"\nend|
             )

    assert [%{context: {:template, {:attribute, "title"}}}] =
             flagged.(
               ~s|defmodule A do\n  def r(assigns), do: ~H"<b title={Date.to_iso8601(@d)}>x</b>"\nend|
             )

    assert [%{context: {:template, :text}}] =
             flagged.(
               ~s|defmodule A do\n  def r(assigns), do: ~H"<b>{Date.to_iso8601(@d)}</b>"\nend|
             )

    assert [] =
             flagged.(
               ~s|defmodule A do\n  def r(assigns), do: ~H"<time datetime={Date.to_iso8601(@d)}>x</time><input value={@d && Date.to_iso8601(@d)} />"\nend|
             )

    assert [%{context: {:code, :label}, what: "Calendar.strftime"}] =
             iso_calls(
               ~s|defmodule A do\n  defp label(at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M")\nend|
             )

    assert [] =
             iso_calls(
               ~s|defmodule A do\n  @doc "Date.to_iso8601/1"\n  defp t(at), do: Calendar.strftime(at, "%H:%M")\nend|
             )
  end

  defp sources do
    "lib/portfolixir_web/**/*.ex"
    |> Path.wildcard()
    |> Enum.reject(fn path -> Enum.any?(@excluded_dirs, &String.starts_with?(path, &1)) end)
  end

  defp offender?(_path, %{context: {:template, _}} = call), do: not machine?(call)

  defp offender?(path, %{context: {:code, function}}),
    do: not Map.has_key?(@allowed, {path, function})

  defp machine?(%{context: {:template, {:attribute, name}}}),
    do:
      name in @machine_attributes or
        Enum.any?(@machine_attribute_prefixes, &String.starts_with?(name, &1))

  defp machine?(_call), do: false

  defp where(%{context: {:template, {:attribute, name}}}), do: " in the #{name} attribute"
  defp where(%{context: {:template, :text}}), do: " in template text"
  defp where(%{context: {:code, function}}), do: " in #{function}"

  # -- the scan ---------------------------------------------------------------

  @iso_formats ~r/%Y-%m|%F/

  # Every ISO date call in `source`: %{line, what, context}, where context is
  # {:code, function} outside a template and {:template, :text} or
  # {:template, {:attribute, name}} inside one.
  defp iso_calls(source) do
    source
    |> Code.string_to_quoted!(columns: false)
    |> walk(nil, [])
    |> Enum.reverse()
  end

  defp walk({kind, _meta, [head | _] = args}, _function, acc)
       when kind in [:def, :defp, :defmacro, :defmacrop] do
    walk(args, function_name(head), acc)
  end

  defp walk({:sigil_H, meta, [{:<<>>, _, parts}, _modifiers]}, _function, acc) do
    template = parts |> Enum.filter(&is_binary/1) |> Enum.join()
    # A heredoc's text starts on the line after its opening quotes.
    first_line = if meta[:delimiter] == ~s("""), do: meta[:line] + 1, else: meta[:line]
    Enum.reverse(template_calls(template, first_line)) ++ acc
  end

  defp walk({{:., _, [{:__aliases__, _, [module]}, fun]}, meta, args} = node, function, acc) do
    acc =
      case iso_call(module, fun, args) do
        nil -> acc
        what -> [%{line: meta[:line], what: what, context: {:code, function}} | acc]
      end

    walk_children(node, function, acc)
  end

  defp walk(node, function, acc), do: walk_children(node, function, acc)

  defp walk_children({left, _meta, right}, function, acc),
    do: walk(right, function, walk(left, function, acc))

  defp walk_children({left, right}, function, acc),
    do: walk(right, function, walk(left, function, acc))

  defp walk_children(list, function, acc) when is_list(list),
    do: Enum.reduce(list, acc, &walk(&1, function, &2))

  defp walk_children(_leaf, _function, acc), do: acc

  defp function_name({:when, _, [head | _]}), do: function_name(head)
  defp function_name({name, _, _}) when is_atom(name), do: name
  defp function_name(_head), do: nil

  defp iso_call(module, :to_iso8601, _args) when module in [:Date, :DateTime, :NaiveDateTime],
    do: "#{module}.to_iso8601"

  defp iso_call(:Date, :to_string, _args), do: "Date.to_string"

  # Piped or not, the format is the call's string argument.
  defp iso_call(:Calendar, :strftime, args) do
    if Enum.any?(args, &(is_binary(&1) and &1 =~ @iso_formats)), do: "Calendar.strftime"
  end

  defp iso_call(_module, _fun, _args), do: nil

  @template_call ~r/(?:Date|DateTime|NaiveDateTime)\.to_iso8601\b|Date\.to_string\b|Calendar\.strftime\([^)]*"[^"]*(?:%Y-%m|%F)/

  # A template is a string to the parser; its expressions are scanned as
  # text, each call classified by where it stands: inside an EEx tag it is
  # text the reader sees; inside `{…}` it is the value of the attribute the
  # brace opens, or text when the brace opens none.
  defp template_calls(template, start_line) do
    for [{offset, length}] <- Regex.scan(@template_call, template, return: :index) do
      before = binary_part(template, 0, offset)
      line = start_line + length(:binary.matches(before, "\n"))
      what = template |> binary_part(offset, length) |> String.replace(~r/\(.*/s, "")

      %{line: line, what: what, context: {:template, template_context(before)}}
    end
  end

  defp template_context(before) do
    if inside_eex?(before), do: :text, else: brace_context(before)
  end

  defp inside_eex?(before) do
    last_open = last_index(before, "<%")
    last_close = last_index(before, "%>")
    last_open != nil and (last_close == nil or last_open > last_close)
  end

  defp brace_context(before) do
    case open_brace(before) do
      nil ->
        :text

      prefix ->
        case Regex.run(~r/([A-Za-z_:][\w:.-]*)=\s*\z/, prefix) do
          [_, name] -> {:attribute, name}
          nil -> :text
        end
    end
  end

  # The text before the innermost unclosed `{` preceding the call, or nil.
  # A `#{` is a string's interpolation inside an expression, not the brace
  # an attribute or a text expression opens, so the walk passes it.
  defp open_brace(before) do
    chars = String.to_charlist(before)

    chars
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.reduce_while(0, fn
      {?}, _index}, depth -> {:cont, depth + 1}
      {?{, index}, 0 -> if hash?(chars, index), do: {:cont, 0}, else: {:halt, {:found, index}}
      {?{, _index}, depth -> {:cont, depth - 1}
      _char, depth -> {:cont, depth}
    end)
    |> case do
      {:found, index} -> chars |> Enum.take(index) |> List.to_string()
      _none -> nil
    end
  end

  defp hash?(chars, index), do: index > 0 and Enum.at(chars, index - 1) == ?#

  defp last_index(text, pattern) do
    case :binary.matches(text, pattern) do
      [] -> nil
      matches -> matches |> List.last() |> elem(0)
    end
  end
end
