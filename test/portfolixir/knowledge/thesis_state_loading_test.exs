defmodule Portfolixir.Knowledge.ThesisStateLoadingTest do
  # E25 S6 (#891), G01: every thesis read — each security detail read carries
  # one — reloaded every stored body of the security's research log, though
  # the projection shows only the current thesis's text. It now reads the
  # log's other fields and loads the one body it shows.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Knowledge
  alias Portfolixir.WorldFixtures

  defp append!(security, attrs) do
    base = %{
      security_id: security.id,
      author: "operator",
      source_quality: "primary",
      as_of: ~D[2026-08-01]
    }

    {:ok, note} = Knowledge.append_note(Actor.owner_ui(), Map.merge(base, attrs))
    note
  end

  defp capture_note_rows(fun) do
    test_pid = self()
    handler = "thesis-state-loading-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:portfolixir, :repo, :query],
      fn _event, _measurements, metadata, _config ->
        with "security_notes" <- metadata[:source],
             {:ok, %{rows: rows}} <- metadata[:result] do
          send(test_pid, {:note_rows, rows})
        end
      end,
      nil
    )

    try do
      result = fun.()
      {result, collect_rows([])}
    after
      :telemetry.detach(handler)
    end
  end

  defp collect_rows(acc) do
    receive do
      {:note_rows, rows} -> collect_rows(acc ++ rows)
    after
      0 -> acc
    end
  end

  # User story:
  # As the operator opening a security whose research log has grown,
  # I want the thesis state read without loading every superseded body,
  # so that a detail read costs what it shows.
  #
  # Acceptance criteria:
  # - The thesis read loads the current thesis's body and no other body.
  # - The state still names the current thesis, its text and its review.
  test "a thesis read loads no superseded body" do
    security = WorldFixtures.create_security!(name: "Inland Barge Co.", ticker: "IBC")

    old =
      append!(security, %{
        kind: "thesis",
        body: "SUPERSEDED-THESIS-BODY: river freight recovers by 2026.",
        as_of: ~D[2026-01-05]
      })

    append!(security, %{
      kind: "evidence",
      body: "EVIDENCE-BODY: volumes up 4% in the quarter.",
      as_of: ~D[2026-03-02]
    })

    current =
      append!(security, %{
        kind: "thesis",
        body: "Fleet renewal lifts margins through 2027.",
        supersedes_id: old.id,
        as_of: ~D[2026-06-01]
      })

    {state, rows} = capture_note_rows(fn -> Knowledge.thesis_state(security.id) end)

    assert state.derived_from_entry_id == current.id
    assert state.thesis == "Fleet renewal lifts margins through 2027."
    assert state.last_reviewed_at == ~D[2026-06-01]

    loaded = rows |> List.flatten() |> Enum.filter(&is_binary/1)
    refute Enum.any?(loaded, &String.starts_with?(&1, "SUPERSEDED-THESIS-BODY"))
    refute Enum.any?(loaded, &String.starts_with?(&1, "EVIDENCE-BODY"))
  end
end
