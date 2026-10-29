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

  defp text(html) do
    html
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace("&nbsp;", "\u00A0")
    |> String.replace(~r/[ \t\n]+/, " ")
    |> String.trim()
  end

  defp statement!(actor, institution, overrides \\ %{}) do
    {:ok, snapshot} =
      Tax.create_snapshot(
        actor,
        Map.merge(
          %{
            institution: institution,
            holder: "Owner",
            tax_year: 2025,
            as_of: ~D[2025-12-31],
            allowance_granted: "1000",
            allowance_used: "0",
            loss_pot_equities: "0"
          },
          overrides
        ),
        today: ~D[2026-01-15]
      )

    snapshot
  end

  defp correct!(actor, snapshot) do
    {:ok, corrected} =
      Tax.update_snapshot(actor, snapshot, %{allowance_used: "10"}, today: ~D[2026-01-15])

    corrected
  end

  # User story (security review 2026-10-12, K12, T-16; board 03 ②):
  # As the operator reading a statement's head on the Tax page,
  # I want its last words to say who recorded it and who corrected it last,
  # so that "recorded manually" is never said of the agent's transcription.
  #
  # Acceptance criteria:
  # - The agent recorded it: "recorded · Agent", hidden lead "Recorded by:",
  #   and not "recorded manually" — also after the operator corrected it.
  # - The operator recorded it and the agent corrected it last: "recorded
  #   manually · corrected · Agent", hidden lead "Last corrected by:".
  # - The operator recorded it and nobody else changed it: "recorded
  #   manually", no mark.
  test "the statement head says who recorded it and who corrected it last", %{conn: conn} do
    by_agent = statement!(Actor.api_token_rw("mcp"), "Bank A")

    agent_then_operator =
      Actor.api_token_rw("mcp") |> statement!("Bank B") |> then(&correct!(Actor.owner_ui(), &1))

    corrected =
      Actor.owner_ui() |> statement!("Bank C") |> then(&correct!(Actor.api_token_rw("mcp"), &1))

    mine = statement!(Actor.owner_ui(), "Bank D")

    {:ok, view, _html} = live(conn, @scope)

    for row <- [by_agent, agent_then_operator] do
      head = row_head(view, row.id)
      assert head =~ ~r/· recorded · Recorded by: Agent$/
      refute head =~ "recorded manually"
    end

    assert row_head(view, corrected.id) =~
             ~r/· recorded manually · corrected · Last corrected by: Agent$/

    assert row_head(view, mine.id) =~ ~r/· recorded manually$/
  end

  # User story (security review 2026-10-12, K12, T-16; board 03 ③, Q3 = A):
  # As the operator reading the tax-free trim budget,
  # I want its basis line to mark each institution whose counted statement
  # the agent recorded or corrected last,
  # so that I know which part of the decision figure rests on the agent's
  # figures.
  #
  # Acceptance criteria:
  # - "(Agent)" follows each such institution, joined by a no-break space,
  #   hidden lead "Statement by:"; the operator's institutions carry none.
  test "the budget's basis line marks the institution the agent's statement covers",
       %{conn: conn} do
    statement!(Actor.owner_ui(), "Bank A")
    statement!(Actor.api_token_rw("mcp"), "Bank B")
    Actor.owner_ui() |> statement!("Bank C") |> then(&correct!(Actor.api_token_rw("mcp"), &1))

    {:ok, view, _html} = live(conn, @scope)
    basis = view |> element("[data-role=budget-basis]") |> render() |> text()

    assert basis =~
             "· Bank A, Bank B\u00A0(Statement by: Agent), Bank C\u00A0(Statement by: Agent)"
  end

  # User story (security review 2026-10-12, K12, T-16; board 03 ②):
  # As the operator comparing the allowance orders with what the banks
  # applied,
  # I want an order the agent put to carry the Agent mark,
  # so that I do not take the agent's instruction for mine.
  #
  # Acceptance criteria:
  # - The list reads "Bank B · Agent" (hidden lead "Allowance order by:");
  #   the closed summary reads "Bank B 400.00 (Agent)"; the operator's order
  #   carries no mark.
  test "an allowance order the agent put is marked in the list and the summary", %{conn: conn} do
    statement!(Actor.owner_ui(), "Bank A")

    {:ok, mine} =
      Tax.put_allowance_order(Actor.owner_ui(), %{
        holder: "Owner",
        institution: "Bank A",
        tax_year: 2025,
        amount_granted: "600"
      })

    {:ok, theirs} =
      Tax.put_allowance_order(Actor.api_token_rw("mcp"), %{
        holder: "Owner",
        institution: "Bank B",
        tax_year: 2025,
        amount_granted: "400"
      })

    {:ok, view, _html} = live(conn, @scope)

    summary = view |> element("[data-role=orders] summary") |> render() |> text()

    assert summary =~
             "Bank A 600.00 · Bank B 400.00\u00A0(Allowance order by: Agent)"

    assert view |> element("#tax-order-#{theirs.id}") |> render() |> text() =~
             "Bank B · Allowance order by: Agent"

    refute view |> element("#tax-order-#{mine.id}") |> render() =~ ~r/\bAgent\b/
  end

  # User story (security review 2026-10-12, K12, T-16):
  # As an agent reading the tax figures,
  # I want the allowance orders and the trim budget to name the agent's
  # writes as the statements do,
  # so that I can tell my own earlier writes from the operator's.
  #
  # Acceptance criteria:
  # - An allowance order reads author and corrected_by; the trim budget
  #   reads agent_institutions beside institutions.
  test "the allowance-order and trim-budget reads name the agent's writes" do
    statement!(Actor.owner_ui(), "Bank A")
    agent_records!()

    put =
      put(api(), "/api/v1/tax/allowance_orders", %{
        "allowance_order" => %{
          "holder" => "Owner",
          "institution" => "Bank A",
          "tax_year" => 2025,
          "amount_granted" => "600"
        }
      })

    assert %{"author" => "agent", "corrected_by" => nil} = json_response(put, 200)["data"]

    [order] = json_response(get(api(), "/api/v1/tax/allowance_orders"), 200)["data"]
    assert {order["author"], order["corrected_by"]} == {"agent", nil}

    budget =
      json_response(get(api(), "/api/v1/tax/trim_budget?holder=Owner&tax_year=2025"), 200)[
        "data"
      ]

    assert budget["institutions"] == ["Bank A", "Example Bank"]
    assert budget["agent_institutions"] == ["Example Bank"]
  end
end
