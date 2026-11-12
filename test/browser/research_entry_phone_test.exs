defmodule PortfolixirWeb.Browser.ResearchEntryPhoneTest do
  # A research entry's headline, label and link on a phone, in a real
  # browser (Sprint 29 N3; board ux-design-2026-11-12-sprint29/03, ④ „A bei
  # 390 px“: the headline wraps, the glyph stays before its first line, and
  # the label wraps as one line). LiveViewTest lays nothing out, so this
  # test boots the endpoint on a free loopback port and measures the entry
  # in Chromium through `research_entry_phone.js` with Playwright.
  #
  # Excluded from the test job (test/test_helper.exs); run it with
  #
  #     mix test test/browser --only browser
  #
  # async: false -- the sandbox is shared with the LiveView processes the
  # browser's requests start. Synthetic data only, no external network.
  use PortfolixirWeb.ConnCase, async: false

  import Portfolixir.NewsFixtures, only: [security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Clock
  alias Portfolixir.Knowledge

  @moduletag :browser
  @moduletag timeout: 120_000

  @script Path.expand("research_entry_phone.js", __DIR__)

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

  # User story (Sprint 29 N3; board 03 ④):
  # As the operator reading a security's research log on my phone,
  # I want a long headline to wrap with the pin's glyph before its first
  # line, and the entry's label and link to stay inside the entry,
  # so that the entry reads as the board draws it at 390 px.
  #
  # Acceptance criteria (a 390 px wide viewport, the Research tab):
  # - the headline of 80 characters wraps, and the glyph's middle is on its
  #   first line, left of it;
  # - the headline, the label line and the link end inside the entry, and
  #   the page does not scroll sideways;
  # - a 400-character link reads its domain;
  # - a superseded entry's label (event type · tone, „maschinell“, „nicht
  #   im Diagramm, weil ersetzt“) wraps, and no line of it starts with the
  #   „·“ (closing act, D3: DESIGN.md S29 N3, the label wraps as one line).
  test "a research entry's headline, label and link fit a 390 px phone", %{base_url: base_url} do
    security = security!("Northwind Harbour Logistics AG")

    {:ok, note} =
      Knowledge.append_note(
        Actor.owner_ui(),
        %{
          "security_id" => security.id,
          "author" => "agent",
          "kind" => "evidence",
          "body" => "Synthetic finding.",
          "source_quality" => "primary",
          "as_of" => Date.to_iso8601(Date.add(Clock.today(), -3)),
          "headline" =>
            "Quarterly report: revenue clearly above the outlook it gave itself in July 2026",
          "event_type" => "capital_measure",
          "tone" => 1,
          "source_url" =>
            "https://news.aggregator.example/articles/redirect?" <>
              String.duplicate("token=abcdef0123456789&", 16) <> "end=1"
        },
        news_label_id: 7
      )

    superseded = superseded!(security)

    args =
      Jason.encode!(%{
        url: base_url <> "/securities/#{security.id}?tab=research",
        entry_id: note.id,
        superseded_id: superseded.id,
        domain: "news.aggregator.example"
      })

    {output, status} = System.cmd("node", [@script, args], stderr_to_stdout: true)

    assert status == 0, "the browser run failed:\n" <> output

    result =
      output
      |> String.split("\n", trim: true)
      |> List.last()
      |> Jason.decode!()

    assert result["ok"] == true, inspect(result)
  end

  # An entry with a headline, an event type, a tone and a news label that a
  # later entry supersedes: its label carries all three parts.
  defp superseded!(security) do
    attrs = %{
      "security_id" => security.id,
      "author" => "agent",
      "kind" => "evidence",
      "body" => "Synthetic finding.",
      "source_quality" => "unverified",
      "as_of" => Date.to_iso8601(Date.add(Clock.today(), -20)),
      "headline" => "Report expects a profit warning",
      "event_type" => "capital_measure",
      "tone" => -1
    }

    {:ok, superseded} = Knowledge.append_note(Actor.owner_ui(), attrs, news_label_id: 7)

    {:ok, _replacing} =
      Knowledge.append_note(
        Actor.owner_ui(),
        Map.merge(attrs, %{
          "as_of" => Date.to_iso8601(Date.add(Clock.today(), -15)),
          "supersedes_id" => superseded.id,
          "headline" => "Board confirms the outlook",
          "tone" => 0
        })
      )

    superseded
  end
end
