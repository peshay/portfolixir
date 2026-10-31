defmodule PortfolixirWeb.CountUpFirstValueTest do
  # #1169 (Sprint 21 γ1; board 01 ①, pick N1 B, the owner's pick of
  # 2026-10-09, the plan's D-3): the CountUp hook paints a first value as it
  # is and counts only from one received figure to the next. The hook is
  # inline JavaScript in `layout_view.ex`, so the guarantee is pinned on its
  # source, as the ModalDialog hook's is.
  use ExUnit.Case, async: true

  defp hook do
    "lib/portfolixir_web/layout_view.ex"
    |> File.read!()
    |> String.split("Hooks.CountUp = {")
    |> Enum.at(1)
    |> String.split("\n            };\n")
    |> hd()
  end

  # User story (#1169, Sprint 21 γ1): As the operator opening the Overview or
  # Wealth, I want the computed total to appear at once as the figure it is,
  # instead of counting up from 0,00, so that no frame on my screen shows a
  # figure the ledger never produced — the Sprint 19 first look read
  # "73.645,32" for 73.657,92.
  #
  # Acceptance criteria:
  # - On its first value (no value received before) the hook starts from the
  #   target itself, so `from === target` and nothing animates: the
  #   server-rendered digits stay as they are.
  # - A later value received in place (Wealth's re-value after the rate
  #   sync) still counts from the previous figure to the new one, with the
  #   settling bar.
  # - Pending is untouched; under `prefers-reduced-motion: reduce` the hook
  #   still never animates.
  test "a first value is painted as it is; a count runs only between two received figures" do
    hook = hook()

    assert hook =~ "var from = this.lastValue === null ? target : this.lastValue;"
    refute hook =~ "this.lastValue === null ? 0"
    assert hook =~ "this.lastValue = target;"
    assert hook =~ "if (from === target || this.reduceMotion()) return;"
    # The count between two received figures keeps its settling state.
    assert hook =~ ~s{el.classList.add("is-settling");}
    assert hook =~ "var current = from + (target - from) * eased;"
  end
end
