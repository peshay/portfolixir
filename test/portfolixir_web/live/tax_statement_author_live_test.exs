defmodule PortfolixirWeb.TaxStatementAuthorLiveTest do
  # Security review 2026-10-12, K12 (decision T-16): a tax statement an API
  # token records or corrects carries an author derived from the actor, the
  # tax reads serialize it, and the Tax page marks the agent's row with the
  # existing Agent mark instead of presenting it as a manual transcription
  # (board 03).
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Tax

  @scope "/tax?holder=Owner&year=2025"

  defp api(conn \\ build_conn()) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp agent_records! do
    conn =
      post(api(), "/api/v1/tax/statement_snapshots", %{
        "statement_snapshot" => %{
          "institution" => "Example Bank",
          "holder" => "Owner",
          "tax_year" => 2025,
          "as_of" => "2025-12-31",
          "allowance_granted" => "1000",
          "allowance_used" => "0",
          "loss_pot_equities" => "25000"
        }
      })

    assert conn.status == 201, "the token's create must succeed: #{conn.resp_body}"
    json_response(conn, 201)["data"]
  end

  defp operator_records! do
    {:ok, snapshot} =
      Tax.create_snapshot(
        Actor.owner_ui(),
        %{
          institution: "Example Bank",
          holder: "Owner",
          tax_year: 2025,
          as_of: ~D[2025-12-31],
          allowance_granted: "1000",
          allowance_used: "1000",
          loss_pot_equities: "0"
        },
        today: ~D[2026-01-15]
      )

    snapshot
  end

  defp row_html(view, id), do: view |> element("#tax-statement-#{id}") |> render()

  defp row_head(view, id) do
    view
    |> element("#tax-statement-#{id} .tax-statement__head .hint")
    |> render()
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp budget_value(html) do
    case Regex.run(~r/data-role="budget-value"[^>]*>\s*([^<]+)</, html) do
      [_, value] -> String.trim(value)
      _ -> nil
    end
  end

  # User story (security review 2026-10-12, K12):
  # As an agent reading the operator's tax statements,
  # I want each statement to name who recorded it,
  # so that a statement a token wrote is not read as the operator's own
  # transcription.
  #
  # Acceptance criteria:
  # - A statement created with an API token reads author agent; its source
  #   stays the system-set manual.
  test "the API read of a statement the agent recorded names the agent as its author" do
    created = agent_records!()

    read =
      json_response(get(api(), "/api/v1/tax/statement_snapshots/#{created["id"]}"), 200)["data"]

    assert read["source"] == "manual"

    assert read["author"] == "agent",
           "a statement written with an API token reads without an author: " <>
             "keys=#{inspect(read |> Map.keys() |> Enum.sort())}, source=#{inspect(read["source"])}"
  end

  # User story (security review 2026-10-12, K12; board 03):
  # As the operator reading the Tax page,
  # I want a statement the agent recorded to carry the Agent mark,
  # so that I do not take the agent's figures, which drive the trim budget,
  # for my own transcription.
  #
  # Acceptance criteria:
  # - The row of a statement a token created carries "Agent".
  test "the Tax page marks a statement the agent recorded", %{conn: conn} do
    created = agent_records!()

    {:ok, view, html} = live(conn, @scope)

    assert budget_value(html) == "26,000.00"

    head = row_head(view, created["id"])

    assert row_html(view, created["id"]) =~ ~r/\bAgent\b/,
           "the agent's statement is shown as the operator's transcription, with no Agent mark: " <>
             inspect(head)
  end

  # User story (security review 2026-10-12, K12; board 03):
  # As the operator whose statement the agent corrected,
  # I want the row to say the agent corrected it last,
  # so that a trim budget moved by the agent's correction is visibly the
  # agent's.
  #
  # Acceptance criteria:
  # - After a token's update of an operator's statement, its row carries
  #   "Agent", while the journal still names the token.
  test "the Tax page marks a statement the agent corrected, whose correction moved the trim budget",
       %{conn: conn} do
    snapshot = operator_records!()

    {:ok, _view, before_html} = live(conn, @scope)
    assert budget_value(before_html) == "0.00"

    patched =
      patch(api(), "/api/v1/tax/statement_snapshots/#{snapshot.id}", %{
        "statement_snapshot" => %{"loss_pot_equities" => "25000"}
      })

    assert patched.status == 200

    assert [%{actor_type: :api_token_rw}] =
             Journal.list_entries(resource_type: "tax_statement_snapshot", operation: :update)

    {:ok, view, after_html} = live(build_conn(), @scope)

    assert budget_value(after_html) == "25,000.00"

    head = row_head(view, snapshot.id)

    assert row_html(view, snapshot.id) =~ ~r/\bAgent\b/,
           "the agent's correction of the operator's statement carries no Agent mark: " <>
             inspect(head)
  end

  # User story (security review 2026-10-12, K12):
  # As the operator recording and correcting my own statement,
  # I want it to read as before,
  # so that the mark stays the exception.
  #
  # Acceptance criteria:
  # - A statement recorded and corrected on the page carries no "Agent" and
  #   reads "recorded manually".
  test "control: a statement recorded and corrected on the page carries no Agent mark",
       %{conn: conn} do
    snapshot = operator_records!()

    {:ok, _updated} =
      Tax.update_snapshot(Actor.owner_ui(), snapshot, %{loss_pot_equities: "100"},
        today: ~D[2026-01-15]
      )

    {:ok, view, _html} = live(conn, @scope)

    refute row_html(view, snapshot.id) =~ ~r/\bAgent\b/
    assert row_head(view, snapshot.id) =~ "recorded manually"
  end
end
