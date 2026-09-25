defmodule PortfolixirWeb.LiveParamSweepTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias PortfolixirWeb.LiveSource

  @web Path.expand("../../../lib/portfolixir_web", __DIR__)

  # The parsers a page must not call on what it is handed: each has a bounded
  # counterpart that every page shares (E25 S4) — an id or a bounded integer
  # through PortfolixirWeb.LiveParam, a date through
  # Portfolixir.Input.BoundedDate, a decimal through
  # Portfolixir.Input.BoundedDecimal.
  @raw_parsers [
    {Integer, :parse},
    {String, :to_integer},
    {Date, :from_iso8601},
    {Decimal, :parse}
  ]

  # User story (E25 S4, F16, F17, #868):
  # As the maintainer adding a page or a control,
  # I want a test to name any page that parses an id, an integer, a date or a
  # decimal by itself,
  # so that the bounded rule every page shares is not bypassed by a local copy
  # the way `/snapshots?snapshot=` and `/tax?year=` once were.
  #
  # Acceptance criteria:
  # - No module of the LiveView layer (the pages, their components and
  #   hooks) calls a raw parser; only PortfolixirWeb.LiveParam wraps one.
  # - The sweep reads real files: the layer has pages, and the rule's own
  #   module does call the parser it wraps.
  test "no page parses an id, an integer, a date or a decimal by itself" do
    files = live_layer_files()
    assert length(files) > 10

    offenders =
      for file <- files,
          Path.basename(file) != "live_param.ex",
          {module, fun, line} <- raw_calls(file),
          do: "#{Path.relative_to(file, @web)}:#{line} #{inspect(module)}.#{fun}"

    assert offenders == [],
           "parse through PortfolixirWeb.LiveParam, BoundedDate or BoundedDecimal:\n" <>
             Enum.join(offenders, "\n")

    assert [{Integer, :parse, _line} | _] = raw_calls(Path.join(@web, "live_param.ex"))
  end

  # User story (E25 S4, F17):
  # As the maintainer,
  # I want every page and component to end its event handling with a clause
  # that ignores what it does not know,
  # so that a new control's event cannot become a crash for every other name.
  #
  # Acceptance criteria:
  # - The last `handle_event/3` clause of every LiveView and LiveComponent
  #   matches any event and any payload.
  test "every page and component ends handle_event with a catch-all clause" do
    {:ok, modules} = :application.get_key(:portfolixir, :modules)

    live_modules =
      Enum.filter(modules, fn module ->
        Code.ensure_loaded?(module) and function_exported?(module, :__live__, 0)
      end)

    assert length(live_modules) > 10

    missing =
      for module <- live_modules, not LiveSource.catch_all_event?(module), do: inspect(module)

    assert missing == [], "no catch-all handle_event/3 in: " <> Enum.join(missing, ", ")
  end

  defp live_layer_files do
    Path.wildcard(Path.join(@web, "live/**/*.ex")) ++
      Path.wildcard(Path.join(@web, "live_*.ex")) ++
      Path.wildcard(Path.join(@web, "components/**/*.ex"))
  end

  defp raw_calls(file) do
    {:ok, ast} = file |> File.read!() |> Code.string_to_quoted()

    {_ast, calls} =
      Macro.prewalk(ast, [], fn
        {{:., meta, [{:__aliases__, _, parts}, fun]}, _, _args} = node, acc ->
          module = Module.concat(parts)

          if {module, fun} in @raw_parsers,
            do: {node, [{module, fun, meta[:line]} | acc]},
            else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(calls)
  end
end
