defmodule Portfolixir.Invariants.CssNumberColoursTest do
  use ExUnit.Case, async: true

  # The number colours, Sprint 23 C2 (the owner's report of 2026-11-02;
  # plan D-11; board ux-design-2026-11-02-sprint23/04-number-colours,
  # pick Q7 C; DESIGN.md → Colors and the stat card's `value-color`).

  @css File.read!("priv/static/app.css")

  # The four token blocks the theme is decided in: the light default, the
  # system-dark media block, and the two forced themes.
  @blocks [
    {":root", ~r/\A:root \{(.*?)\n\}/s, :light},
    {"prefers-color-scheme: dark",
     ~r/@media \(prefers-color-scheme: dark\) \{\s*:root \{(.*?)\n  \}/s, :dark},
    {~s([data-theme="light"]), ~r/\n\[data-theme="light"\] \{(.*?)\n\}/s, :light},
    {~s([data-theme="dark"]), ~r/\n\[data-theme="dark"\] \{(.*?)\n\}/s, :dark}
  ]

  @brand %{
    light: %{"color-positive" => "#0f766e", "color-danger" => "#ce1b42"},
    dark: %{"color-positive" => "#2dd4bf", "color-danger" => "#fb7185"}
  }

  # User story (Sprint 23 C2; the owner's report of 2026-11-02):
  # As the operator who picked the teal accent,
  # I want a gain to be the one green the app has and a loss the one red,
  # so that a teal figure and an emerald gain no longer sit side by side as
  # two greens, and a loss is the same red as a problem note.
  #
  # Acceptance criteria:
  # - In all four token blocks `--color-positive` is an alias of the brand
  #   teal (`var(--color-accent-teal)`) and `--color-danger` of the brand
  #   coral (`var(--color-accent-coral)`), whatever accent `[data-accent]`
  #   sets: no literal of its own, so the app has one green and one red.
  # - They resolve to light #0f766e / #ce1b42 and dark #2dd4bf / #fb7185.
  # - No `[data-accent]` block re-keys either of them.
  test "a gain is the brand teal and a loss the brand coral in every theme block" do
    for {name, regex, mode} <- @blocks do
      tokens = tokens(regex)

      assert tokens["color-positive"] == "var(--color-accent-teal)",
             "#{name}: --color-positive is #{inspect(tokens["color-positive"])}, not the brand teal"

      assert tokens["color-danger"] == "var(--color-accent-coral)",
             "#{name}: --color-danger is #{inspect(tokens["color-danger"])}, not the brand coral"

      for {token, hex} <- @brand[mode] do
        assert resolve(tokens, token) == hex, "#{name}: --#{token} resolves to another colour"
      end
    end

    for accent <- ~w(violet teal coral) do
      [body] =
        Regex.run(~r/\n\[data-accent="#{accent}"\] \{(.*?)\n\}/s, @css, capture: :all_but_first)

      refute body =~ ~r/--color-(positive|danger)\s*:/,
             ~s([data-accent="#{accent}"] re-keys a gain or loss colour)
    end
  end

  defp tokens(regex) do
    [body] = Regex.run(regex, @css, capture: :all_but_first)

    ~r/--([\w-]+)\s*:\s*([^;]+);/
    |> Regex.scan(body, capture: :all_but_first)
    |> Map.new(fn [name, value] -> {name, String.trim(value)} end)
  end

  defp root_tokens, do: tokens(~r/\A:root \{(.*?)\n\}/s)

  # A block re-keys only what changes; anything it leaves out falls back to
  # `:root`. An alias resolves in the block that declares it.
  defp resolve(tokens, name) do
    case Map.get(tokens, name) || Map.fetch!(root_tokens(), name) do
      "var(--" <> rest -> resolve(tokens, String.trim_trailing(rest, ")"))
      value -> value
    end
  end
end
