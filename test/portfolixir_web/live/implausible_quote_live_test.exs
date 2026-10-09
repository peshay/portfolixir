defmodule PortfolixirWeb.ImplausibleQuoteLiveTest do
  # #1101 (Sprint 20 β B4, plan D-7; board ux-design-2026-10-07/02-money-findings,
  # pick L2 A, problem severity): a held security whose stored quotes
  # contradict its own bookings is named where the data-quality family
  # names things — the securities list's removable chip, the Overview's
  # data-quality line and Wealth's notes.
  #
  # The data is the board's, invented: "Arbolia Inc." (USD) sold 03.04.2026
  # at 61,40 with no quote that day and 618,90 the day before; "Wrenfield
  # Gardens AG" (EUR) bought 12.05.2026 at 48,20 with 4,87 that day.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, put_quote!: 3]

  defp german(conn), do: Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")

  defp wrenfield!(world) do
    wrenfield = create_security!(name: "Wrenfield Gardens AG", ticker: "WGA")
    buy!(world, wrenfield, quantity: "120", price: "48.20", date: ~D[2026-05-12])
    put_quote!(wrenfield, ~D[2026-05-12], "4.87")
    wrenfield
  end

  # User story (#1101; board 02, L2 A, the securities list):
  # As the operator following the finding to its list,
  # I want the list opened on exactly the named securities under a
  # removable chip that says why,
  # so that I see the set and can clear the filter.
  #
  # Acceptance criteria:
  # - /securities?dq=implausible_quote lists Wrenfield and not a security
  #   whose quotes match its bookings, under the removable chip "Kurs passt
  #   nicht zu Buchungen" (German) / "Quote does not match bookings"
  #   (English); there is no one-tap chip for it.
  test "the securities list opens on the set under a removable chip", %{conn: conn} do
    world = base_world(name: "Depot")
    wrenfield!(world)

    plain = create_security!(name: "Halden Robotics AG", ticker: "HRB")
    buy!(world, plain, quantity: "30", price: "10.00", date: ~D[2024-01-10])
    put_quote!(plain, ~D[2024-01-10], "10.20")

    {:ok, list, _html} = live(german(conn), "/securities?dq=implausible_quote")
    assert has_element?(list, "#filter-chips .chip", "Kurs passt nicht zu Buchungen")
    assert has_element?(list, "td", "Wrenfield Gardens AG")
    refute has_element?(list, "td", "Halden Robotics AG")
    refute has_element?(list, "#sec-chip-implausible_quote")

    {:ok, list, _html} = live(conn, "/securities?dq=implausible_quote")
    assert has_element?(list, "#filter-chips .chip", "Quote does not match bookings")
  end
end
