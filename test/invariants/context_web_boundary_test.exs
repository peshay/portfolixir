defmodule Portfolixir.Invariants.ContextWebBoundaryTest do
  use ExUnit.Case, async: true

  # User story:
  # As the owner who reviews decisions rather than diffs,
  # I want a meta-test that fails when a module under lib/portfolixir/
  # references a web-layer module outside the registered exceptions,
  # so that AGENTS.md's "contexts never depend on the web layer" is a gate
  # that holds, not a sentence the code contradicts unnoticed.
  #
  # Acceptance criteria:
  # - Every alias of a `PortfolixirWeb` module in code under lib/portfolixir/
  #   is either registered below with its reason or fails the test.
  # - The scan is AST-based, so a module named in a comment, a doc string or
  #   a string literal never counts.
  # - A registered exception that no longer occurs fails too, so the list
  #   never outlives the code it excuses.
  #
  # Source: the rule review of 2026-11-12 (I9, R26) found the rule text
  # contradicted by eleven Gettext lines and the OTP boot modules, with no
  # check on this direction (`web_repo_boundary_test.exs` checks the other).

  @context_sources Path.wildcard("lib/portfolixir/**/*.ex")

  # {file or :any, the web module} => why the context may name it.
  @registered %{
    {:any, PortfolixirWeb.Gettext} =>
      "the one Gettext backend: a context that writes a sentence the operator " <>
        "reads (an import's refusal, a field's label) translates it with the " <>
        "catalogue the screens use, so there is one set of .po files",
    {"lib/portfolixir/application.ex", PortfolixirWeb.Endpoint} =>
      "the OTP application starts the endpoint as a child and forwards " <>
        "config_change/3; it is the boot of the whole release, not a domain context",
    {"lib/portfolixir/application.ex", PortfolixirWeb.SocketCrashReport} =>
      "the OTP application installs the socket crash report on boot, " <>
        "config-gated; boot wiring, not a domain context",
    {"lib/portfolixir/release.ex", PortfolixirWeb.Endpoint} =>
      "the release tasks (migrate, seed) load the endpoint's config with the " <>
        "server off; release tooling, not a domain context"
  }

  test "no module under lib/portfolixir/ names a web module outside the registered exceptions" do
    found = references()

    offenders =
      for {path, module} <- found, not registered?(path, module) do
        "#{path}: #{inspect(module)}"
      end

    assert offenders == [],
           "A context names a web-layer module (AGENTS.md, Architecture). Move the " <>
             "dependency or register it here with its reason:\n" <> Enum.join(offenders, "\n")
  end

  test "every registered exception still occurs" do
    found = references()

    stale =
      for {{scope, module}, _why} <- @registered,
          not Enum.any?(found, fn {path, m} ->
            m == module and (scope == :any or scope == path)
          end) do
        "#{inspect(scope)}: #{inspect(module)}"
      end

    assert stale == [], "Registered exceptions that no longer occur:\n" <> Enum.join(stale, "\n")
  end

  defp registered?(path, module),
    do: Map.has_key?(@registered, {:any, module}) or Map.has_key?(@registered, {path, module})

  defp references do
    for path <- @context_sources,
        module <- web_aliases(File.read!(path)),
        uniq: true,
        do: {path, module}
  end

  defp web_aliases(source) do
    {_ast, acc} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        {:__aliases__, _meta, [:PortfolixirWeb | _rest] = segments} = node, acc ->
          {node, [Module.concat(segments) | acc]}

        node, acc ->
          {node, acc}
      end)

    acc
  end
end
