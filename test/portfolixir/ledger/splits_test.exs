defmodule Portfolixir.Ledger.SplitsTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, put_quote!: 3, sell!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Clock
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
  # - A half-landed retry (one portfolio already carries the identical row)
  #   is completed idempotently: only the missing rows are inserted, the
  #   existing row is never duplicated (E17 review, finding 2).
  # - Once every positioned portfolio carries the row, booking again fails
  #   with {:error, {:existing_split, tx}} naming an already-booked row.
  test "rejects a second same-day split naming the existing event, atomically" do
    world_a = base_world(name: "Retry A", cash_name: "RA Cash", depot_name: "RA Depot")
    world_b = base_world(name: "Retry B", cash_name: "RB Cash", depot_name: "RB Depot")
    security = create_security!(name: "Retry Co", ticker: "RTY")
    buy!(world_a, security, quantity: "10", price: "100", date: ~D[2026-01-02])
    buy!(world_b, security, quantity: "6", price: "100", date: ~D[2026-01-02])

    # Portfolio B already carries the split (e.g. a half-landed retry booked
    # manually): re-booking completes the fan-out with A's missing row only.
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

    assert {:ok, [completion]} = Splits.book_split(Actor.owner_ui(), split_attrs(security))
    assert completion.portfolio_id == world_a.portfolio.id

    split_rows =
      Ledger.list_transactions(security_id: security.id)
      |> Enum.filter(&(&1.type == "split"))

    assert split_rows |> Enum.map(& &1.id) |> Enum.sort() ==
             Enum.sort([existing.id, completion.id])

    # With every positioned portfolio booked, a retry names the existing
    # event and writes nothing.
    assert {:error, {:existing_split, %Transaction{type: "split"}}} =
             Splits.book_split(Actor.owner_ui(), split_attrs(security))

    assert length(
             Enum.filter(
               Ledger.list_transactions(security_id: security.id),
               &(&1.type == "split")
             )
           ) == 2
  end

  # User story (ADR-0028 §5, issue #589):
  # As a local portfolio maintainer,
  # I want a future-dated effective date rejected deterministically,
  # so that a split can never scale positions that do not exist yet.
  #
  # Acceptance criteria:
  # - A future effective date returns {:error, :future_effective_date} from
  #   both preview and book.
  # Issue #609: the boundary is the HOST's day. East of UTC, a split effective
  # today used to be rejected as future between local and UTC midnight.
  test "accepts a split effective on the host's local today" do
    world = base_world(name: "Local World", cash_name: "L Cash", depot_name: "L Depot")
    security = create_security!(name: "Local Co", ticker: "LOC")
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-02])

    assert {:ok, _preview} =
             Splits.preview_split(split_attrs(security, date: Clock.today()))

    assert {:ok, _booked} =
             Splits.book_split(Actor.owner_ui(), split_attrs(security, date: Clock.today()))
  end

  test "rejects a future-dated effective date in preview and book" do
    world = base_world(name: "Future World", cash_name: "F Cash", depot_name: "F Depot")
    security = create_security!(name: "Future Co", ticker: "FUT")
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-02])

    tomorrow = Date.add(Clock.today(), 1)

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
             :no_position_at_effective_date,
             :insufficient_quotes_to_verify_basis
           ]

    assert [row] = preview.portfolios
    assert row.portfolio_id == world.portfolio.id
    assert row.bookable == false
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

  # User story (E17 closing-act review, finding 2 — extend fan-out):
  # As a local portfolio maintainer who backdated a buy into a portfolio
  # after booking the security's split,
  # I want re-booking the identical split to insert only the missing
  # portfolio rows,
  # so that the late-positioned portfolio's holdings scale without me
  # deleting and re-creating the whole event.
  #
  # Acceptance criteria:
  # - Re-booking an identical (security, date, normalized ratio) split skips
  #   portfolios that already carry the row and inserts only the missing ones.
  # - When no portfolio is missing the booking still returns
  #   {:error, {:existing_split, tx}}.
  test "re-booking an identical split extends the fan-out to newly positioned portfolios" do
    world_a = base_world(name: "Extend A", cash_name: "XA Cash", depot_name: "XA Depot")
    world_b = base_world(name: "Extend B", cash_name: "XB Cash", depot_name: "XB Depot")
    world_c = base_world(name: "Extend C", cash_name: "XC Cash", depot_name: "XC Depot")
    security = create_security!(name: "Extend Co", ticker: "XTD")
    buy!(world_a, security, quantity: "10", price: "100", date: ~D[2026-01-02])
    buy!(world_b, security, quantity: "4", price: "100", date: ~D[2026-01-02])

    assert {:ok, first} = Splits.book_split(Actor.owner_ui(), split_attrs(security))
    assert length(first) == 2

    # Portfolio C becomes positioned at the effective date only afterwards,
    # via a backdated booking.
    buy!(world_c, security, quantity: "6", price: "100", date: ~D[2026-01-15])

    assert {:ok, [extension]} = Splits.book_split(Actor.owner_ui(), split_attrs(security))
    assert extension.portfolio_id == world_c.portfolio.id
    assert extension.type == "split"
    assert Decimal.equal?(position(world_c, security), Decimal.new("12"))

    # Existing rows were not duplicated.
    split_rows =
      Ledger.list_transactions(security_id: security.id)
      |> Enum.filter(&(&1.type == "split"))

    assert length(split_rows) == 3

    # With every positioned portfolio already booked the retry answer stays
    # the existing-event rejection.
    assert {:error, {:existing_split, %Transaction{}}} =
             Splits.book_split(Actor.owner_ui(), split_attrs(security))
  end

  # User story (E17 closing-act review, finding 2 — same-day ratio guard):
  # As a maintainer of an auditable quote history,
  # I want a booking with a different ratio on a day that already carries a
  # split rejected (and flagged in the preview),
  # so that conflicting security-level events can never corrupt the quote
  # consumers that dedupe rows into one event per (security, date).
  #
  # Acceptance criteria:
  # - Booking a different normalized ratio on the same (security, date)
  #   returns {:error, {:conflicting_split_ratio, tx}} naming an existing row.
  # - The preview of such a booking warns with :conflicting_split_ratio.
  test "rejects a same-day split with a different ratio and warns in preview" do
    world = base_world(name: "Conflict World", cash_name: "CF Cash", depot_name: "CF Depot")
    security = create_security!(name: "Conflict Co", ticker: "CFL")
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-02])

    assert {:ok, [existing]} = Splits.book_split(Actor.owner_ui(), split_attrs(security))

    conflicting = split_attrs(security, numerator: 3, denominator: 1)

    assert {:error, {:conflicting_split_ratio, %Transaction{id: id}}} =
             Splits.book_split(Actor.owner_ui(), conflicting)

    assert id == existing.id

    assert {:ok, preview} = Splits.preview_split(conflicting)
    assert :conflicting_split_ratio in preview.warnings
  end

  # User story (E17 closing-act review, finding 3 — re-preview double-scale):
  # As a local portfolio maintainer re-opening the split wizard after booking,
  # I want the preview of an already-booked split to show the real resulting
  # position and say the event is already booked,
  # so that the simulation never stacks a synthetic split on top of the
  # booked row and shows a double-scaled position.
  #
  # Acceptance criteria:
  # - Re-previewing a booked 2:1 split on a 10-share buy shows
  #   current_position 20, not 40.
  # - The preview carries the :already_booked warning.
  test "re-previewing an already-booked split does not double-scale the current position" do
    world = base_world(name: "Reprev World", cash_name: "RP Cash", depot_name: "RP Depot")
    security = create_security!(name: "Reprev Co", ticker: "RPV")
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-02])

    assert {:ok, _} = Splits.book_split(Actor.owner_ui(), split_attrs(security))

    assert {:ok, preview} = Splits.preview_split(split_attrs(security))
    assert :already_booked in preview.warnings

    assert [row] = preview.portfolios
    assert Decimal.equal?(row.quantity_before, Decimal.new("10"))
    assert Decimal.equal?(row.quantity_after, Decimal.new("20"))
    assert Decimal.equal?(row.current_position, Decimal.new("20"))
  end

  # User story (E17 closing-act review, finding 4 — int4 bound):
  # As an API consumer sending an oversized ratio part,
  # I want values beyond the int4 column range rejected as :invalid_ratio,
  # so that the request fails with a clean validation error instead of a
  # database exception.
  #
  # Acceptance criteria:
  # - Ratio parts above 2_147_483_647 (integer or string-encoded) return
  #   {:error, :invalid_ratio} from preview and book.
  test "rejects ratio parts beyond the int4 range as invalid" do
    world = base_world(name: "Int4 World", cash_name: "I4 Cash", depot_name: "I4 Depot")
    security = create_security!(name: "Int4 Co", ticker: "IN4")
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-02])

    assert {:error, :invalid_ratio} =
             Splits.preview_split(split_attrs(security, numerator: 3_000_000_000))

    assert {:error, :invalid_ratio} =
             Splits.preview_split(split_attrs(security, denominator: 3_000_000_000))

    assert {:error, :invalid_ratio} =
             Splits.preview_split(%{split_attrs(security) | ratio_numerator: "3000000000"})

    assert {:error, :invalid_ratio} =
             Splits.book_split(Actor.owner_ui(), split_attrs(security, numerator: 3_000_000_000))

    # The upper bound itself is still a valid integer.
    assert {:ok, _} =
             Splits.preview_split(split_attrs(security, numerator: 2_147_483_647))
  end

  # User story (E17 closing-act review, finding 5 — preview/book divergence):
  # As an operator whose portfolios were all flat at the effective date while
  # one holds the security today,
  # I want each preview row to say whether booking would create a row for it
  # and the preview to warn when nothing is bookable,
  # so that a warning-free preview can never diverge silently from a booking
  # that fails with :no_position.
  #
  # Acceptance criteria:
  # - Every preview row carries bookable: true/false (false when
  #   quantity_before is zero).
  # - With no bookable row the preview warns :no_position_at_effective_date
  #   while book returns {:error, :no_position}.
  test "preview flags unbookable rows and warns when book would return :no_position" do
    world_a = base_world(name: "Div A", cash_name: "DivA Cash", depot_name: "DivA Depot")
    world_b = base_world(name: "Div B", cash_name: "DivB Cash", depot_name: "DivB Depot")
    security = create_security!(name: "Div Co", ticker: "DIV")

    # A sold out before the effective date, B bought only after it.
    buy!(world_a, security, quantity: "10", price: "100", date: ~D[2026-01-05])
    sell!(world_a, security, quantity: "10", price: "100", date: ~D[2026-01-10])
    buy!(world_b, security, quantity: "5", price: "50", date: ~D[2026-02-01])

    # Clean 2:1 jump across the effective date, so the §2 basis guard reports
    # :consistent and cannot mask the missing warning.
    put_quote!(security, ~D[2026-01-19], "100")
    put_quote!(security, ~D[2026-01-20], "50")

    attrs = %{
      security_id: security.id,
      date: ~D[2026-01-20],
      ratio_numerator: 2,
      ratio_denominator: 1
    }

    assert {:ok, preview} = Splits.preview_split(attrs)
    assert :no_position_at_effective_date in preview.warnings

    assert [row] = preview.portfolios
    assert row.portfolio_id == world_b.portfolio.id
    assert row.bookable == false
    assert Decimal.equal?(row.quantity_before, Decimal.new("0"))

    assert {:error, :no_position} = Splits.book_split(Actor.owner_ui(), attrs)

    # A positioned portfolio previews as bookable.
    buy!(world_a, security, quantity: "3", price: "100", date: ~D[2026-01-15])
    assert {:ok, preview} = Splits.preview_split(attrs)
    refute :no_position_at_effective_date in preview.warnings

    assert %{bookable: true} =
             Enum.find(preview.portfolios, &(&1.portfolio_id == world_a.portfolio.id))
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
