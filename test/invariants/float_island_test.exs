defmodule Portfolixir.Invariants.FloatIslandTest do
  @moduledoc """
  AR-3 (`_bmad-output/planning-artifacts/epics.md`): Decimal discipline
  admits a contained float island for the operations `Decimal` does not
  have, **only for those, each one named**, each encoded as an explicit,
  tested exception and not a loophole. Widening the list needs an ADR.

  This gate makes the list mechanical: every `:math` call (and `Float.pow/2`
  and the power operator `**`) in the domain (`lib/portfolixir/**`) must be
  registered below with the record that named it, and every registered
  operation must still be there. `:math` reached any other way (an alias, an
  import, `apply/3`, a variable) is found as the atom and can never be
  registered: a float operation is called by its name.
  A new float operation, or an existing one copied into another module,
  fails the build until a record names it.

  The web layer (`lib/portfolixir_web/**`) is outside the scan: it draws
  (chart geometry, axis ticks, a contrast ratio) and computes no figure that
  a payload serves; every figure it shows comes from a domain read.
  """
  use ExUnit.Case, async: true

  @sources Path.wildcard("lib/portfolixir/**/*.ex")

  # {file, function/arity} => the record that named it. AR-3 counts four
  # operations; `:math.pow/2` is one operation used in three places.
  @registered %{
    # AR-3's original exception: the IRR solver's Newton step.
    {"lib/portfolixir/portfolios/performance/irr.ex", "pow/2"} => "AR-3; ADR-0047 §4",
    # The daily compounding factor of a fixed-rate benchmark.
    {"lib/portfolixir/portfolios/performance/benchmark.ex", "pow/2"} => "ADR-0046; ADR-0047 §4",
    # The standard deviation and the correlation (FR-39, FR-40).
    {"lib/portfolixir/engines/statistics.ex", "sqrt/1"} => "ADR-0047 §4",
    # The analog band's price side: the logarithm of a cycle's factor and
    # the one step back (FR-58).
    {"lib/portfolixir/engines/cycles.ex", "log/1"} => "ADR-0060 §4",
    {"lib/portfolixir/engines/cycles.ex", "pow/2"} => "ADR-0060 §4"
  }

  # User story (AR-3, amended 2026-11-12 by ADR-0060 §4; Sprint 29 H5):
  # As the maintainer holding Decimal discipline,
  # I want every float operation in the domain registered with the record
  # that named it,
  # so that the island widens only by a decision, never by a call nobody
  # reviewed.
  #
  # Acceptance criteria:
  # - The `:math` and `Float.pow/2` calls under `lib/portfolixir/` are exactly
  #   the registered ones: none unregistered, none registered and gone.
  # - `:math.log/1` is registered, for the analog band only (ADR-0060 §4),
  #   as AR-3's fourth operation beside `:math.pow/2` and `:math.sqrt/1`.
  test "the domain's float operations are exactly AR-3's registered ones" do
    found =
      for path <- @sources,
          operation <- float_operations(File.read!(path)),
          uniq: true,
          do: {path, operation}

    unregistered = Enum.reject(found, &Map.has_key?(@registered, &1))
    gone = @registered |> Map.keys() |> Enum.reject(&(&1 in found))

    assert unregistered == [],
           "AR-3: a float operation outside the registered island; widening it needs " <>
             "an ADR and an entry here: #{inspect(unregistered)}"

    assert gone == [],
           "AR-3: a registered float operation is no longer in its module; take it off " <>
             "the list: #{inspect(gone)}"

    operations = found |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Enum.sort()
    assert operations == ["log/1", "pow/2", "sqrt/1"]
  end

  # Acceptance criteria (the gate's attack case, story workflow "What a
  # story's own tests do not cover"):
  # - A call, a pipe into `:math`, a capture and `Float.pow/2` are each
  #   found; a mention in a comment or a string is not.
  test "the scan finds every call form and ignores prose" do
    source = """
    defmodule Attack do
      # :math.exp(1.0) in a comment is prose
      def a(x), do: :math.exp(x)
      def b(x), do: x |> :math.log10()
      def c, do: &:math.tanh/1
      def d(x), do: Float.pow(x, 2.0)
      def e, do: ":math.cos(1.0)"
    end
    """

    assert Enum.sort(float_operations(source)) ==
             ["Float.pow/2", "exp/1", "log10/1", "tanh/1"]
  end

  # Acceptance criteria (the closing act's analytics lens on Lane H, finding
  # 4: three forms the scan missed):
  # - `:math` reached any other way than a direct call, pipe or capture —
  #   an alias, an import, `apply/3`, a variable — is found as the atom
  #   itself, which no record registers.
  # - The power operator `**`, written, called through `Kernel` or
  #   captured, is found as `**/2`: it answers a float for a float or a
  #   negative exponent, so it needs a record as `:math.pow/2` does.
  # - A direct call still counts once, not again as its atom.
  test "the scan finds an aliased :math, apply on :math and the power operator" do
    cases = [
      {"alias :math, as: M\n  def f(x), do: M.log(x)", ["the atom :math"]},
      {"import :math, only: [log: 1]\n  def f(x), do: log(x)", ["the atom :math"]},
      {"def f(x), do: apply(:math, :log, [x])", ["the atom :math"]},
      {"def f(x) do\n    m = :math\n    m.log(x)\n  end", ["the atom :math"]},
      {"def f(x), do: x ** 0.5", ["**/2"]},
      {"def f(x), do: Kernel.**(x, 0.5)", ["**/2"]},
      {"def f, do: &**/2", ["**/2"]},
      {"def f(x), do: :math.log(x)", ["log/1"]}
    ]

    for {body, expected} <- cases do
      source = "defmodule Attack do\n  #{body}\nend\n"
      assert float_operations(source) == expected, body
    end
  end

  # Every `:math.fun(args)` (arity counted with a pipe's left side),
  # `&:math.fun/n` and `Float.pow/2`, as "fun/arity"; the power operator,
  # however written, as "**/2"; and the atom `:math` anywhere else (an
  # alias, an import, `apply/3`, a variable), as "the atom :math". A counted
  # call is replaced by its arguments, so its own `:math` is not seen again
  # and only the arguments are walked; a capture by an atom.
  defp float_operations(source) do
    {_ast, found} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        # The pipe counts its left side in the arity; the call is not
        # walked again, its left side and its arguments are.
        {:|>, _meta, [left, {{:., _, [:math, fun]}, _, args}]}, acc ->
          {[left | args], ["#{fun}/#{length(args) + 1}" | acc]}

        {:&, _meta, [{:/, _, [{{:., _, [:math, fun]}, _, []}, arity]}]}, acc ->
          {:captured, ["#{fun}/#{arity}" | acc]}

        {{:., _, [:math, fun]}, _meta, args}, acc when is_list(args) ->
          {args, ["#{fun}/#{length(args)}" | acc]}

        {{:., _, [{:__aliases__, _, [:Float]}, :pow]}, _meta, args} = node, acc
        when length(args) == 2 ->
          {node, ["Float.pow/2" | acc]}

        # `x ** y`, `Kernel.**(x, y)` and `&**/2`.
        {:&, _meta, [{:/, _, [{:**, _, context}, 2]}]}, acc when is_atom(context) ->
          {:captured, ["**/2" | acc]}

        {:**, _meta, args}, acc when is_list(args) ->
          {args, ["**/2" | acc]}

        {{:., _, [{:__aliases__, _, [:Kernel]}, :**]}, _meta, args}, acc when is_list(args) ->
          {args, ["**/2" | acc]}

        :math, acc ->
          {:math, ["the atom :math" | acc]}

        node, acc ->
          {node, acc}
      end)

    found
  end
end
