defmodule PortfolixirWeb.Browser.NotePinsPhoneTest do
  # The chart's note pins on a phone, in a real browser (Sprint 28 closing
  # act, ND3; board ux-design-2026-11-08-sprint28/01, marker A). The pins
  # are drawn in the chart's 960-unit viewBox, which a 390 px phone scales
  # to about a third: a head of 13 units was under 5 px, and its glyph, the
  # tone's second channel (UX-DR7), could not be read. LiveViewTest runs no
  # client script and lays nothing out, so this test boots the endpoint on
  # a free loopback port and measures the pins in Chromium through
  # `note_pins_phone.js` with Playwright, after the ChartCrosshair hook has
  # written --chart-upx.
  #
  # Excluded from the test job (test/test_helper.exs); run it with
  #
  #     mix test test/browser --only browser
  #
  # async: false -- the sandbox is shared with the LiveView processes the
  # browser's requests start. Synthetic data only, no external network.
  use PortfolixirWeb.ConnCase, async: false

  import Portfolixir.NewsFixtures, only: [security!: 1]
  import Portfolixir.WorldFixtures, only: [put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Clock
  alias Portfolixir.Knowledge

  @moduletag :browser
  @moduletag timeout: 120_000

  @script Path.expand("note_pins_phone.js", __DIR__)

  setup do
    server =
      PortfolixirWeb.TestListener.start!(
        {Bandit,
         plug: PortfolixirWeb.Endpoint,
         scheme: :http,
         ip: {127, 0, 0, 1},
         port: 0,
         startup_log: false}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    %{base_url: "http://localhost:#{port}"}
  end

  defp day(offset), do: Date.add(Clock.today(), offset)

  defp note!(security, offset, headline, tone) do
    {:ok, _note} =
      Knowledge.append_note(Actor.owner_ui(), %{
        "security_id" => security.id,
        "author" => "operator",
        "kind" => "evidence",
        "body" => "Synthetic finding.",
        "source_quality" => "primary",
        "as_of" => Date.to_iso8601(day(offset)),
        "headline" => headline,
        "event_type" => "guidance",
        "tone" => tone
      })
  end

  # User story (ND3; UX-DR7):
  # As the operator reading a security's chart on my phone,
  # I want each note pin's head and glyph large enough to read,
  # so that I tell a good day from a bad and a mixed one without relying on
  # colour.
  #
  # Acceptance criteria (a 390 px wide viewport, the Diagramm tab):
  # - every pin's head is at least 10 CSS px across;
  # - a positive, a negative and a mixed pin each carry a glyph at least
  #   5 CSS px across, the mixed one its own (±); a neutral pin none.
  test "the note pins keep their size and glyph on a 390 px phone", %{base_url: base_url} do
    security = security!("Northwind Harbour Logistics AG")
    put_quotes!(security, for(n <- 100..1//-1, do: {day(-n), "#{100 + rem(n, 7)}"}))
    note!(security, -80, "Capital raise funds the terminal", 1)
    note!(security, -60, "Suit filed", -1)
    note!(security, -40, "Outlook kept", 0)
    note!(security, -30, "Outlook kept again", 0)
    note!(security, -30, "New product line", 1)

    {output, status} =
      System.cmd("node", [@script, base_url <> "/securities/#{security.id}?tab=chart"],
        stderr_to_stdout: true
      )

    assert status == 0, "the browser run failed:\n" <> output

    result =
      output
      |> String.split("\n", trim: true)
      |> List.last()
      |> Jason.decode!()

    assert result["ok"] == true, inspect(result)
  end
end
