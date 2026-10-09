defmodule Portfolixir.Invariants.CssStatusRegionTest do
  use ExUnit.Case, async: true

  # #1119 (the Sprint 20 plan's D-4): an empty status region waiting for its
  # note leaves the flow with `position: absolute`, the idiom app.css already
  # uses for the page result slot in a section's grid, instead of
  # `display: none`, which takes it out of the accessibility tree. The rules
  # are CSS and markup, so the stylesheet and the templates are what this
  # test reads.

  @css File.read!("priv/static/app.css")

  @regions %{
    "merge-region" => [
      "lib/portfolixir_web/live/securities/merge_preview.ex",
      "lib/portfolixir_web/live/portfolio_accounts/merge_preview.ex"
    ],
    "booking-delete__region" => ["lib/portfolixir_web/live/transactions/booking_delete_dialog.ex"],
    "wealth-card-status" => ["lib/portfolixir_web/live/dashboard_live.ex"],
    "category-result-excluded-region" => ["lib/portfolixir_web/live/classifications_live.ex"]
  }

  # User story (#1119):
  # As an operator using a screen reader,
  # I want the Overview's exclusion note, a merge dialog's changed-plan note
  # or refusal, the booking delete's changed-split note and the
  # classification screen's note on the members its result leaves out (the
  # Sprint 20 γ closing act) announced when they arrive,
  # so that I hear them, which a region hidden with `display: none` while
  # empty does not promise: it enters the accessibility tree together with
  # its note.
  #
  # Acceptance criteria:
  # - The empty regions (`.merge-region`, `.booking-delete__region`,
  #   `.wealth-card-status`, `.category-result-excluded-region`) leave the
  #   flow with `position: absolute`, and no rule gives them `display: none`.
  # - The picture is identical: no other rule styles these regions, so the
  #   out-of-flow empty box has no padding, border, background or size and
  #   paints nothing, and as an out-of-flow child it takes no row and no gap
  #   of its container's grid, as before.
  # - Each region is a `role` live region whose markup holds nothing but its
  #   note, no whitespace, so `:empty` holds while there is none (a
  #   `data-role` after its class is allowed).
  # - DESIGN.md prescribes `position: absolute` for the empty region, not
  #   `display: none`.
  test "an empty status region leaves the flow and stays in the accessibility tree" do
    [_, selectors, body] =
      Regex.run(
        ~r/\n((?:\.(?:merge-region|booking-delete__region|wealth-card-status|category-result-excluded-region):empty,?\s*)+)\{([^}]*)\}/,
        @css
      )

    assert selectors |> String.split(~r/[,\s]+/, trim: true) |> Enum.sort() ==
             Enum.sort(for class <- Map.keys(@regions), do: ".#{class}:empty")

    assert String.trim(body) == "position: absolute;"

    for {class, templates} <- @regions do
      # The :empty rule is the only rule that names the region.
      assert length(Regex.scan(~r/\.#{Regex.escape(class)}\b/, @css)) == 1, class

      for template <- templates do
        source = File.read!(template)

        assert source =~
                 ~r/<div (id="[^"]+" )?role="(status|alert)" class="#{class}"( data-role="[^"]+")?><[.A-Z]/,
               "#{template}: the #{class} region holds its note and no whitespace"
      end
    end

    design =
      "_bmad-output/planning-artifacts/design-language/DESIGN.md"
      |> File.read!()
      |> String.replace(~r/\s+/, " ")

    assert design =~ "`.wealth-card-status:empty { position: absolute }`"
    refute design =~ "`.wealth-card-status:empty { display: none }`"
  end
end
