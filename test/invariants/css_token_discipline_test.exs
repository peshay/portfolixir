defmodule Portfolixir.Invariants.CssTokenDisciplineTest do
  use ExUnit.Case, async: true

  # User story:
  # As a maintainer fighting CSS drift,
  # I want a meta-test that fails when a raw hex colour is added outside the
  # design-token definitions,
  # so that the colour system in `priv/static/app.css` converges on the `--color-*`
  # tokens instead of accumulating one-off hard-coded values (the recurring source
  # of the "why isn't this consistent?" papercuts).
  #
  # Acceptance criteria:
  # - Hex literals are allowed ONLY on custom-property definition lines
  #   (`--name: #hex;`), where the tokens themselves live.
  # - Every other hex (e.g. `color: #ffffff`, `var(--x, #fallback)`) counts as a
  #   raw colour and must use a token instead.
  # - The count is a ratchet: it may only go DOWN. New raw hex fails the build;
  #   cleanup PRs lower @max_raw_hex. (Tracked under the CSS-consistency epic.)

  @css_path "priv/static/app.css"

  # Ratchet baseline measured 2026-06-18. ONLY lower this — never raise it.
  @max_raw_hex 57

  @hex ~r/#[0-9a-fA-F]{3,8}\b/
  @token_def ~r/^\s*--[\w-]+\s*:/

  test "raw hex colours outside token definitions do not increase (ratchet)" do
    offenders =
      @css_path
      |> File.read!()
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, lineno} ->
        if Regex.match?(@token_def, line) do
          []
        else
          for _match <- Regex.scan(@hex, line), do: "#{@css_path}:#{lineno}: #{String.trim(line)}"
        end
      end)

    count = length(offenders)

    assert count <= @max_raw_hex, """
    Raw hex colours outside token definitions rose to #{count} (allowed: #{@max_raw_hex}).
    Use a `--color-*` token (var(...)) instead of a hard-coded hex value.
    Offending lines:
    #{Enum.join(offenders, "\n")}
    """

    # Keep the ratchet tight: if you removed raw hex, lower @max_raw_hex.
    if count < @max_raw_hex do
      IO.warn(
        "CSS raw-hex count dropped to #{count}; lower @max_raw_hex in " <>
          "#{__ENV__.file |> Path.relative_to_cwd()} to keep the ratchet tight."
      )
    end
  end
end
