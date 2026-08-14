defmodule PortfolixirWeb.ApiV1DeltaReadsTest do
  # FR-38 / issue #666: `?since=` delta reads on the two recurring-sync
  # reads (transactions and securities), so an agent's recurring run fetches
  # what changed instead of pulling the full state and diffing it against a
  # local copy. The push half stays gated at B3.7 — that boundary is pinned
  # here as its own acceptance criterion.
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Repo
  alias PortfolixirWeb.Api.V1.SinceParam

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp owner, do: Portfolixir.Actor.owner_ui()

  defp seed_world do
    {:ok, portfolio} =
      Portfolios.create_portfolio(owner(), %{name: "Delta", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(owner(), %{
        portfolio_id: portfolio.id,
        name: "Delta Cash",
        currency_code: "EUR"
      })

    %{portfolio: portfolio, cash: cash}
  end

  defp create_deposit!(world, date) do
    {:ok, transaction} =
      Ledger.create_transaction(owner(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        type: "deposit",
        date: date,
        gross_amount: "100.00",
        currency_code: "EUR"
      })

    transaction
  end

  # Test-only clock control: backdate a row's updated_at so the delta cut
  # has something on both sides. The journal guard requires an actor for any
  # write, so the transaction-local actor is set first (sandbox-scoped).
  defp backdate!(table, id, naive) when table in ["transactions", "securities"] do
    Repo.query!("SELECT set_config('portfolixir.journal_actor', 'test_backdate', true)")
    Repo.query!("UPDATE #{table} SET updated_at = $1 WHERE id = $2", [naive, id])
  end

  # User story (FR-38, issue #666):
  # As the operating LLM agent on a recurring run,
  # I want `?since=<ISO8601>` on the transactions read,
  # so that I fetch the rows created or updated since my last run instead of
  # pulling the whole ledger and diffing it locally.
  #
  # Acceptance criteria:
  # - Only rows with updated_at strictly after `since` (UTC) return.
  # - The response echoes `since`, carries `as_of` (the read instant, usable
  #   as the next `since`) and a `delta_note` stating the semantics —
  #   including that deletions are NOT represented (a caller that must
  #   detect deletions performs a full read).
  # - An invalid `since` is a 422; the plain read is unchanged.
  test "transactions ?since= returns only rows changed after the cut", %{conn: conn} do
    world = seed_world()
    old = create_deposit!(world, ~D[2026-01-02])
    new = create_deposit!(world, ~D[2026-01-03])
    backdate!("transactions", old.id, ~N[2026-01-02 08:00:00])

    response =
      conn
      |> api_conn()
      |> get("/api/v1/transactions?since=2026-06-01T00:00:00Z")
      |> json_response(200)

    assert Enum.map(response["data"], & &1["id"]) == [new.id]
    assert response["since"] == "2026-06-01T00:00:00Z"
    assert is_binary(response["as_of"])
    assert response["delta_note"] =~ "Deletions are not represented"

    # The plain read is unchanged: both rows, no delta envelope.
    plain = conn |> api_conn() |> get("/api/v1/transactions") |> json_response(200)
    assert length(plain["data"]) == 2
    refute Map.has_key?(plain, "delta_note")

    assert conn
           |> api_conn()
           |> get("/api/v1/transactions?since=yesterdayish")
           |> json_response(422)
  end

  test "transactions ?since= composes with fields= and accepts a plain date", %{conn: conn} do
    world = seed_world()
    old = create_deposit!(world, ~D[2026-01-02])
    _new = create_deposit!(world, ~D[2026-01-03])
    backdate!("transactions", old.id, ~N[2026-01-02 08:00:00])

    response =
      conn
      |> api_conn()
      |> get("/api/v1/transactions?since=2026-06-01&fields=id,type")
      |> json_response(200)

    assert [row] = response["data"]
    assert Map.keys(row) |> Enum.sort() == ["id", "type"]
  end

  # User story (FR-38, issue #666):
  # As the operating LLM agent keeping a catalog state file,
  # I want `?since=` on the securities read,
  # so that a recurring catalog sync transfers only what changed.
  #
  # Acceptance criteria:
  # - Only securities with updated_at strictly after `since` return.
  # - The delta envelope (since / as_of / delta_note) travels with it.
  # - An invalid `since` is a 422.
  test "securities ?since= returns only rows changed after the cut", %{conn: conn} do
    {:ok, old} =
      Catalog.create_security(owner(), %{name: "Old Equity", currency_code: "EUR"})

    {:ok, new} =
      Catalog.create_security(owner(), %{name: "New Equity", currency_code: "EUR"})

    backdate!("securities", old.id, ~N[2026-01-02 08:00:00])

    response =
      conn
      |> api_conn()
      |> get("/api/v1/securities?since=2026-06-01T00:00:00Z")
      |> json_response(200)

    assert Enum.map(response["data"], & &1["id"]) == [new.id]
    assert response["since"] == "2026-06-01T00:00:00Z"
    assert is_binary(response["as_of"])
    assert response["delta_note"] =~ "Deletions are not represented"

    assert conn
           |> api_conn()
           |> get("/api/v1/securities?since=not-a-time")
           |> json_response(422)
  end

  # User story (FR-38, issue #666, review finding):
  # As an agent polling with `?since=`,
  # I want `as_of` captured BEFORE the query runs,
  # so that a row committed between the query and the stamp falls into the
  # next poll's window (overlap) instead of being skipped forever by the
  # strictly-after cut.
  #
  # Acceptance criteria:
  # - `SinceParam.parse/1` captures the read instant at parse time.
  # - `put_envelope/2` serializes exactly that pre-query stamp, never a
  #   fresh `DateTime.utc_now/0` taken at render time.
  test "as_of is the parse-time stamp, not a render-time one" do
    {:ok, parsed} = SinceParam.parse(%{"since" => "2026-06-01"})

    assert %DateTime{} = parsed.as_of

    pinned = DateTime.new!(~D[2026-06-02], ~T[08:00:00], "Etc/UTC")
    envelope = SinceParam.put_envelope(%{data: []}, %{parsed | as_of: pinned})

    assert envelope.as_of == "2026-06-02T08:00:00Z"
  end

  # Issue #666's own boundary: the push half (webhooks to user-configured
  # endpoints) stays gated at B3.7 and is deliberately NOT part of this
  # surface. Pinned against the documentation so scoping it in later
  # requires changing this stated boundary consciously.
  test "the docs state that delta reads are pull-only and push delivery stays gated (B3.7)" do
    docs = File.read!(Path.join(File.cwd!(), "docs/integration/api-and-mcp.md"))

    assert docs =~ "pull-only"
    assert docs =~ "B3.7"
  end
end
