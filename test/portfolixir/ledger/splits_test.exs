defmodule Portfolixir.Ledger.SplitsTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, sell!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Ledger.Transaction

  defp split_attrs(security, opts \\ []) do
    %{
      security_id: security.id,
      date: Keyword.get(opts, :date, ~D[2026-02-02]),
      ratio_numerator: Keyword.get(opts, :numerator, 2),
      ratio_denominator: Keyword.get(opts, :denominator, 1)
    }
  end

  defp position(world, security) do
    world.portfolio.id
    |> Ledger.positions_for_portfolio()
    |> Map.get({world.depot.id, security.id})
  end

  # User story (ADR-0028 §1, issue #589):
  # As a local portfolio maintainer whose security split across several
  # portfolios,
  # I want one "split security X at ratio R on date D" request to fan out
  # into one ledger row per portfolio holding a position at the effective
  # date,
  # so that I book the security-level fact once while each portfolio's
  # holdings scale from its own auditable event row.
  #
  # Acceptance criteria:
  # - preview_split/1 returns one row per positioned portfolio with the
  #   portfolio name, the quantity before/after the split (exact Decimal)
  #   and the resulting current position.
  # - book_split/2 inserts one `split` transaction per positioned portfolio
  #   atomically; a zero-position portfolio gets no row.
  # - The rows share the natural-key group identity
  #   (security_id, date, normalized ratio) — no extra grouping column.
  test "fans a split out to every positioned portfolio and skips zero-position portfolios" do
    world_a = base_world(name: "Split A", cash_name: "A Cash", depot_name: "A Depot")
    world_b = base_world(name: "Split B", cash_name: "B Cash", depot_name: "B Depot")
    world_c = base_world(name: "Split C", cash_name: "C Cash", depot_name: "C Depot")
    security = create_security!(name: "Fanout Co", ticker: "FAN")

    buy!(world_a, security, quantity: "10", price: "100", date: ~D[2026-01-02])
    buy!(world_b, security, quantity: "4", price: "100", date: ~D[2026-01-02])
    # Portfolio C is flat again before the effective date: no row for it.
    buy!(world_c, security, quantity: "5", price: "100", date: ~D[2026-01-02])
    sell!(world_c, security, quantity: "5", price: "110", date: ~D[2026-01-10])

    assert {:ok, preview} = Splits.preview_split(split_attrs(security))
    assert preview.security_id == security.id
    assert preview.date == ~D[2026-02-02]
    assert preview.ratio_numerator == 2
    assert preview.ratio_denominator == 1
    # No quotes exist in this world, so the §2 basis guard reports exactly
    # the insufficient-quotes warning — and nothing else.
    assert preview.warnings == [:insufficient_quotes_to_verify_basis]

    assert [row_a, row_b] = Enum.sort_by(preview.portfolios, & &1.portfolio_id)
    assert row_a.portfolio_id == world_a.portfolio.id
    assert row_a.portfolio_name == "Split A"
    assert Decimal.equal?(row_a.quantity_before, Decimal.new("10"))
    assert Decimal.equal?(row_a.quantity_after, Decimal.new("20"))
    assert Decimal.equal?(row_a.current_position, Decimal.new("20"))
    assert row_b.portfolio_id == world_b.portfolio.id
    assert Decimal.equal?(row_b.quantity_before, Decimal.new("4"))
    assert Decimal.equal?(row_b.quantity_after, Decimal.new("8"))
    assert Decimal.equal?(row_b.current_position, Decimal.new("8"))

    assert {:ok, transactions} = Splits.book_split(Actor.owner_ui(), split_attrs(security))
    assert length(transactions) == 2

    for tx <- transactions do
      assert %Transaction{type: "split"} = tx
      assert tx.security_id == security.id
      assert tx.date == ~D[2026-02-02]
      assert tx.split_ratio_numerator == 2
      assert tx.split_ratio_denominator == 1
    end

    booked_portfolios = transactions |> Enum.map(& &1.portfolio_id) |> Enum.sort()
    assert booked_portfolios == Enum.sort([world_a.portfolio.id, world_b.portfolio.id])

    assert Decimal.equal?(position(world_a, security), Decimal.new("20"))
    assert Decimal.equal?(position(world_b, security), Decimal.new("8"))
    assert Ledger.positions_for_portfolio(world_c.portfolio.id) == %{}
  end

  # User story (ADR-0028 §1, issue #589):
  # As a local portfolio maintainer entering a split ratio as stated by my
  # broker,
  # I want the ratio pair normalized to lowest terms at write time,
  # so that event identity and equality always use the canonical pair.
  #
  # Acceptance criteria:
  # - A 10:5 request previews and books as 2:1.
  test "normalizes the ratio to lowest terms (10:5 books as 2:1)" do
    world = base_world(name: "Norm World", cash_name: "N Cash", depot_name: "N Depot")
    security = create_security!(name: "Norm Co", ticker: "NRM")
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-02])

    assert {:ok, preview} =
             Splits.preview_split(split_attrs(security, numerator: 10, denominator: 5))

    assert preview.ratio_numerator == 2
    assert preview.ratio_denominator == 1

    assert {:ok, [tx]} =
             Splits.book_split(
               Actor.owner_ui(),
               split_attrs(security, numerator: 10, denominator: 5)
             )

    assert tx.split_ratio_numerator == 2
    assert tx.split_ratio_denominator == 1
  end

  # User story (ADR-0017 / ADR-0028 §5, issue #589):
  # As the maintainer of an auditable local ledger,
  # I want every row of a fanned-out split booking journaled individually
  # with the acting identity,
  # so that each portfolio's split event is attributable on its own.
  #
  # Acceptance criteria:
  # - Each created split row has exactly one `create` journal entry.
  # - The entry records the actor that booked the split.
  test "journals one entry per created split row with the actor recorded" do
    world_a = base_world(name: "Journal A", cash_name: "JA Cash", depot_name: "JA Depot")
    world_b = base_world(name: "Journal B", cash_name: "JB Cash", depot_name: "JB Depot")
    security = create_security!(name: "Journal Co", ticker: "JRN")
    buy!(world_a, security, quantity: "10", price: "100", date: ~D[2026-01-02])
    buy!(world_b, security, quantity: "6", price: "100", date: ~D[2026-01-02])

    actor = Actor.api_token_rw("split-suite")
    assert {:ok, transactions} = Splits.book_split(actor, split_attrs(security))
    assert length(transactions) == 2

    for tx <- transactions do
      assert [entry] =
               Journal.list_entries(
                 resource_type: "transaction",
                 resource_id: to_string(tx.id),
                 operation: :create
               )

      assert entry.actor_type == :api_token_rw
      assert entry.actor_label == "split-suite"
      assert entry.after["type"] == "split"
      assert entry.after["split_ratio_numerator"] == 2
    end
  end

  # User story (ADR-0028 §1, issue #589):
  # As a local portfolio maintainer,
  # I want a split against a security no portfolio holds to be rejected,
  # so that meaningless events cannot enter the ledger.
  #
  # Acceptance criteria:
  # - A security without any position returns {:error, :no_position} from
  #   preview and book.
  test "rejects a split when no portfolio holds a position" do
    base_world(name: "Empty World", cash_name: "E Cash", depot_name: "E Depot")
    security = create_security!(name: "Unheld Co", ticker: "UNH")

    assert {:error, :no_position} = Splits.preview_split(split_attrs(security))
    assert {:error, :no_position} = Splits.book_split(Actor.owner_ui(), split_attrs(security))
  end

  # User story (ADR-0028 §1 write idempotency, issue #589):
  # As an MCP operator whose booking request timed out and was retried,
  # I want a second same-day split for the same security rejected with the
  # existing event named,
  # so that a retry can never compound the multiplicative event.
  #
  # Acceptance criteria:
  # - Booking the same split twice fails with {:error, {:existing_split, tx}}
  #   where tx is the already-booked row.
  # - The failed booking writes nothing (atomic fan-out): a conflict on one
  #   portfolio rolls back the whole request.
  test "rejects a second same-day split naming the existing event, atomically" do
    world_a = base_world(name: "Retry A", cash_name: "RA Cash", depot_name: "RA Depot")
    world_b = base_world(name: "Retry B", cash_name: "RB Cash", depot_name: "RB Depot")
    security = create_security!(name: "Retry Co", ticker: "RTY")
    buy!(world_a, security, quantity: "10", price: "100", date: ~D[2026-01-02])
    buy!(world_b, security, quantity: "6", price: "100", date: ~D[2026-01-02])

    # Portfolio B already carries the split (e.g. a half-landed retry booked
    # manually): the fan-out must conflict on B and leave A without a row.
    {:ok, existing} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world_b.portfolio.id,
        security_id: security.id,
        type: "split",
        date: ~D[2026-02-02],
        currency_code: "EUR",
        split_ratio_numerator: 2,
        split_ratio_denominator: 1
      })

    assert {:error, {:existing_split, named}} =
             Splits.book_split(Actor.owner_ui(), split_attrs(security))

    assert named.id == existing.id
    assert named.type == "split"
    assert named.split_ratio_numerator == 2
    assert named.split_ratio_denominator == 1

    split_rows =
      Ledger.list_transactions(security_id: security.id)
      |> Enum.filter(&(&1.type == "split"))

    assert [%{id: id}] = split_rows
    assert id == existing.id

    # A clean retry against a fully booked split is rejected the same way.
    {:ok, _} = Ledger.delete_transaction(Actor.owner_ui(), existing)
    assert {:ok, booked} = Splits.book_split(Actor.owner_ui(), split_attrs(security))
    assert length(booked) == 2

    assert {:error, {:existing_split, %Transaction{}}} =
             Splits.book_split(Actor.owner_ui(), split_attrs(security))
  end

  # User story (ADR-0028 §5, issue #589):
  # As a local portfolio maintainer,
  # I want a future-dated effective date rejected deterministically,
  # so that a split can never scale positions that do not exist yet.
  #
  # Acceptance criteria:
  # - A future effective date returns {:error, :future_effective_date} from
  #   both preview and book.
  test "rejects a future-dated effective date in preview and book" do
    world = base_world(name: "Future World", cash_name: "F Cash", depot_name: "F Depot")
    security = create_security!(name: "Future Co", ticker: "FUT")
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-02])

    tomorrow = Date.add(Date.utc_today(), 1)

    assert {:error, :future_effective_date} =
             Splits.preview_split(split_attrs(security, date: tomorrow))

    assert {:error, :future_effective_date} =
             Splits.book_split(Actor.owner_ui(), split_attrs(security, date: tomorrow))
  end

  # User story (ADR-0028 §1 last paragraph, issue #589):
  # As a maintainer whose imported history may already be post-split (the PP
  # split wizard rewrites history destructively),
  # I want the preview to warn when the effective date predates the
  # security's earliest transaction,
  # so that I can recognise an already-adjusted history before booking.
  #
  # Acceptance criteria:
  # - The preview returns the :effective_date_before_history warning and
  #   shows the (zero) quantity before/after next to the current position.
  # - Booking such a split is rejected with {:error, :no_position}: no
  #   portfolio holds anything at the effective date, so there is nothing
  #   to scale.
  test "warns when the effective date predates the security's earliest transaction" do
    world = base_world(name: "History World", cash_name: "H Cash", depot_name: "H Depot")
    security = create_security!(name: "History Co", ticker: "HST")
    buy!(world, security, quantity: "30", price: "100", date: ~D[2026-01-10])

    assert {:ok, preview} = Splits.preview_split(split_attrs(security, date: ~D[2026-01-05]))

    assert preview.warnings == [
             :effective_date_before_history,
             :insufficient_quotes_to_verify_basis
           ]

    assert [row] = preview.portfolios
    assert row.portfolio_id == world.portfolio.id
    assert Decimal.equal?(row.quantity_before, Decimal.new("0"))
    assert Decimal.equal?(row.quantity_after, Decimal.new("0"))
    assert Decimal.equal?(row.current_position, Decimal.new("30"))

    assert {:error, :no_position} =
             Splits.book_split(Actor.owner_ui(), split_attrs(security, date: ~D[2026-01-05]))
  end

  # User story (ADR-0028 §1, issue #589):
  # As an API consumer sending unchecked input to the dedicated split flow,
  # I want invalid ratios, dates and unknown securities rejected with
  # deterministic errors,
  # so that the shell can translate each failure into a precise response.
  #
  # Acceptance criteria:
  # - Non-positive or non-integer ratio parts return {:error, :invalid_ratio}.
  # - A pair that normalizes to 1:1 returns {:error, :identity_ratio}.
  # - An unknown security returns {:error, :security_not_found}.
  # - An unparseable date returns {:error, :invalid_date}.
  test "rejects invalid ratio, identity ratio, unknown security and bad date" do
    world = base_world(name: "Validate World", cash_name: "V Cash", depot_name: "V Depot")
    security = create_security!(name: "Validate Co", ticker: "VAL")
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-02])

    assert {:error, :invalid_ratio} = Splits.preview_split(split_attrs(security, numerator: 0))

    assert {:error, :invalid_ratio} =
             Splits.preview_split(split_attrs(security, denominator: -3))

    assert {:error, :invalid_ratio} =
             Splits.preview_split(%{split_attrs(security) | ratio_numerator: "x"})

    for {p, q} <- [{1, 1}, {5, 5}] do
      assert {:error, :identity_ratio} =
               Splits.preview_split(split_attrs(security, numerator: p, denominator: q))
    end

    assert {:error, :security_not_found} =
             Splits.preview_split(%{split_attrs(security) | security_id: security.id + 1000})

    assert {:error, :invalid_date} =
             Splits.preview_split(%{split_attrs(security) | date: "not-a-date"})

    assert {:error, :invalid_ratio} =
             Splits.book_split(Actor.owner_ui(), split_attrs(security, numerator: 0))
  end

  # User story (ADR-0028 §1, issue #589):
  # As an API shell passing JSON parameters through,
  # I want the context to accept string keys and string-encoded values,
  # so that the controller does not duplicate parsing logic.
  #
  # Acceptance criteria:
  # - String-keyed attrs with string ids, ISO date and string ratio parts
  #   preview and book exactly like native-typed attrs.
  test "accepts string keys, ISO date strings and string-encoded integers" do
    world = base_world(name: "String World", cash_name: "S Cash", depot_name: "S Depot")
    security = create_security!(name: "String Co", ticker: "STR")
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-02])

    attrs = %{
      "security_id" => to_string(security.id),
      "date" => "2026-02-02",
      "ratio_numerator" => "10",
      "ratio_denominator" => "5"
    }

    assert {:ok, preview} = Splits.preview_split(attrs)
    assert preview.ratio_numerator == 2
    assert preview.ratio_denominator == 1
    assert [row] = preview.portfolios
    assert Decimal.equal?(row.quantity_after, Decimal.new("20"))

    assert {:ok, [tx]} = Splits.book_split(Actor.owner_ui(), attrs)
    assert tx.date == ~D[2026-02-02]
    assert tx.split_ratio_numerator == 2
  end
end
