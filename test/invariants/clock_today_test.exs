defmodule Portfolixir.Invariants.ClockTodayTest do
  # E25 S6 (#891), G08: domain date checks used three clocks — UTC
  # (`Date.utc_today/0`), the BEAM's local zone (`Portfolixir.Clock`) and the
  # database session's zone (`CURRENT_DATE` in the policy-rule trigger) —
  # so "today" could differ between two checks of one write. Every "today"
  # default now reads `Portfolixir.Clock.today/0`, and the database session
  # takes the BEAM's zone on connect. This meta-test keeps the UTC clock out
  # of the code, AST-based, so a mention in a doc string never counts.
  use ExUnit.Case, async: true

  # The one place UTC is the right day: the "changed since" presets are
  # compared with UTC timestamps, and an ISO date there means the start of
  # that UTC day (the API's `since=` contract).
  @allowed ["lib/portfolixir_web/components/changed_since.ex"]

  # User story:
  # As the operator of an instance east or west of UTC,
  # I want every "today" the product decides with to be the same day,
  # so that a check never accepts a date another check of the same write
  # refuses.
  #
  # Acceptance criteria:
  # - No module under lib/ calls `Date.utc_today/0` outside the allow-list.
  # - Every allow-listed file does call it, so the list never outlives its
  #   reason.
  test "no code reads the calendar day in UTC outside the allow-list" do
    offenders =
      for path <- Path.wildcard("lib/**/*.ex"),
          path not in @allowed,
          line <- utc_today_calls(File.read!(path)) do
        "#{path}:#{line}"
      end

    assert offenders == [],
           "Read the calendar day through Portfolixir.Clock.today/0 (E25 S6, G08):\n" <>
             Enum.join(offenders, "\n")

    for path <- @allowed do
      assert utc_today_calls(File.read!(path)) != [],
             "#{path} no longer calls Date.utc_today/0; remove it from the allow-list"
    end
  end

  test "the scan finds a call and ignores a mention" do
    assert utc_today_calls("defmodule A do\n  def x, do: Date.utc_today()\nend") == [2]

    assert utc_today_calls(~s|defmodule A do\n  @doc "Date.utc_today/0"\n  def x, do: 1\nend|) ==
             []

    assert utc_today_calls(
             "defmodule A do\n  def r(assigns), do: ~H\"<i>{Date.utc_today()}</i>\"\nend"
           ) == [2]
  end

  defp utc_today_calls(source) do
    {_ast, lines} =
      source
      |> Code.string_to_quoted!(columns: false)
      |> Macro.prewalk([], fn
        {{:., _, [{:__aliases__, _, [:Date]}, :utc_today]}, meta, _args} = node, acc ->
          {node, [meta[:line] | acc]}

        # A HEEx template is a string to the parser; its expressions are
        # scanned as text.
        {:sigil_H, meta, [{:<<>>, _, parts}, _modifiers]} = node, acc ->
          calls =
            for part <- parts,
                is_binary(part),
                _ <- Regex.scan(~r/Date\.utc_today\(/, part),
                do: meta[:line]

          {node, calls ++ acc}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(lines)
  end
end
