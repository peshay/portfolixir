defmodule Portfolixir.Imports.CouponReimportTest do
  # ADR-0051 I11 (the amendment of 2026-10-09; risk-tier: import idempotency,
  # ADR-0036). Before the amendment the importer stored an INTEREST row
  # without the security it names. An instance that imported a bond's coupon
  # then must book nothing when the same file is dropped again, nor when a
  # re-export of it moved the coupon's time of day: the first is all hash
  # hits, the second misses the hash and is found by the economic key read
  # with no security (`DedupKey.of/1`, the applier's pre-import check).
  #
  # "Applied before the build" is rebuilt from today's import: the file is
  # applied and every interest booking's security is cleared, which is what
  # the importer stored then. Every name, ISIN and amount is synthetic.
  #
  # async: false: the applier's after-commit enrichment runs in a task that
  # needs the shared sandbox connection.
  use Portfolixir.DataCase, async: false

  import Ecto.Query

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier.Result
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios

  @fixtures Path.expand("../../support/fixtures/portfolio_performance", __DIR__)

  # bond_invented.json: a deposit, a buy and one coupon naming its bond;
  # bond_coupon.json (I12): a deposit, a buy, an account interest naming no
  # security and a coupon naming its bond.
  @files [{"bond_invented.json", 3}, {"bond_coupon.json", 4}]

  # The coupon of bond_coupon.json, as the file writes it, and the same row
  # re-exported with its time of day moved.
  @coupon_time ~s("time": "09:30")
  @moved_time ~s("time": "09:31")

  # Two bonds paying an equal coupon on one day, to one account, at one time:
  # before the amendment the second collapsed onto the first (ADR-0050 §6).
  @twin_coupons """
  {
    "version": 1,
    "transactions": [
      {"type": "DEPOSIT", "account": "Twin-Cash", "date": "2025-01-02",
       "currency": "EUR", "amount": 1000.00},
      {"type": "INTEREST", "account": "Twin-Cash", "date": "2026-05-15",
       "time": "08:00", "currency": "EUR", "amount": 50.00,
       "security": {"name": "Wrenfield Gardens AG 5,00 % Anleihe 2030",
                    "isin": "XSWRENFLD206", "currency": "EUR"}},
      {"type": "INTEREST", "account": "Twin-Cash", "date": "2026-05-15",
       "time": "08:00", "currency": "EUR", "amount": 50.00,
       "security": {"name": "Larkspur Rail AG 4,00 % Anleihe 2031",
                    "isin": "XSLARKSPUR33", "currency": "EUR"}}
    ]
  }
  """

  setup do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Coupon re-import",
        base_currency_code: "EUR"
      })

    %{portfolio: portfolio}
  end

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))

  defp parse!(body, filename) do
    {:ok, preview} = PortfolioPerformance.parse(body, filename: filename)
    assert preview.errors == []
    preview
  end

  defp apply!(body, name, portfolio) do
    assert {:ok, %Result{} = result} =
             Imports.apply(parse!(body, name), %{portfolio_id: portfolio.id})

    result
  end

  # What the importer stored before the amendment: every interest booking
  # without its security (a test actor for the journal guard; nothing but
  # the security changes).
  defp clear_coupon_securities!(portfolio) do
    {:ok, _cleared} =
      Repo.transaction(fn ->
        Repo.query!("SELECT set_config('portfolixir.journal_actor', 'test', true)")

        from(t in Transaction, where: t.portfolio_id == ^portfolio.id and t.type == "interest")
        |> Repo.update_all(set: [security_id: nil])
      end)

    :ok
  end

  defp counts do
    %{
      cash: Portfolios.count_cash_accounts(),
      depots: length(Portfolios.list_securities_accounts()),
      securities: Catalog.count_securities(),
      transactions: Ledger.count_transactions()
    }
  end

  # User story (#928, Sprint 21 α4; ADR-0051 I11):
  # As the operator whose instance imported a bond's coupons before the
  # importer kept their security,
  # I want dropping the same Portfolio Performance file again to book
  # nothing,
  # so that the importer's change never books a coupon of mine twice.
  #
  # Acceptance criteria:
  # - Each file, applied with its coupons stored without a security, then
  #   dropped again, inserts no transaction and creates no cash account,
  #   depot or security.
  # - Every row is a hash hit, in the result and in the preview's count.
  test "a file applied before the importer kept a coupon's security books nothing when dropped again",
       %{portfolio: portfolio} do
    for {name, rows} <- @files do
      first = apply!(fixture(name), name, portfolio)
      assert first.created_transactions == rows, name
      clear_coupon_securities!(portfolio)

      before = counts()

      counted = Imports.reimport_counts(parse!(fixture(name), name), portfolio_id: portfolio.id)
      assert counted.total.hash == rows, name
      assert counted.total.new == 0, name

      again = apply!(fixture(name), name, portfolio)
      assert again.created_transactions == 0, name
      assert again.already_imported == %{hash: rows, retired: 0, economics: 0}, name
      assert counts() == before, name
    end
  end

  # User story (#928, Sprint 21 α4; ADR-0051 I11):
  # As the operator whose instance imported a bond's coupon before the
  # importer kept its security,
  # I want a re-export of the same history whose coupon moved its time of day
  # to book nothing either,
  # so that a coupon stored without its bond is still recognised once the
  # importer stores the bond with every new one.
  #
  # Acceptance criteria:
  # - bond_coupon.json applied with its coupons stored without a security,
  #   then re-exported with the coupon at 09:31 instead of 09:30: the coupon
  #   misses its content hash and is found by its economic key, read with no
  #   security.
  # - Nothing is inserted or created (zero transactions, accounts, depots and
  #   securities); the result names the coupon's row under `economics`, and
  #   the preview counts it there too.
  test "a re-export whose coupon moved its time books nothing, found by the key with no security",
       %{portfolio: portfolio} do
    name = "bond_coupon.json"
    apply!(fixture(name), name, portfolio)
    clear_coupon_securities!(portfolio)

    moved = String.replace(fixture(name), @coupon_time, @moved_time)
    refute moved == fixture(name)

    before = counts()

    counted = Imports.reimport_counts(parse!(moved, name), portfolio_id: portfolio.id)
    assert counted.total.hash == 3
    assert counted.total.economics == 1
    assert counted.total.new == 0

    again = apply!(moved, name, portfolio)
    assert again.created_transactions == 0
    assert again.already_imported == %{hash: 3, retired: 0, economics: 1}
    assert [%{row: 4}] = Enum.filter(again.duplicate_entries, &(&1.layer == :economics))
    assert counts() == before
  end

  # User story (#928, Sprint 21 α4; ADR-0051 I11 and point 4):
  # As the operator whose instance imported two bonds' equal coupons from one
  # file while the importer collapsed them into one booking,
  # I want dropping that file again to book nothing,
  # so that the importer no longer collapsing such a pair does not book the
  # second coupon now.
  #
  # Acceptance criteria:
  # - The file applied as it was then (the deposit and the first coupon
  #   booked, the coupon without a security; the second coupon collapsed
  #   onto it, its bond created), then dropped again: the deposit and the
  #   first coupon are hash hits, the second coupon is found by the economic
  #   key read with no security, and nothing is inserted or created.
  test "a pair of equal coupons collapsed by an earlier import books nothing when dropped again",
       %{portfolio: portfolio} do
    apply!(@twin_coupons, "twin.json", portfolio)
    collapse_second_coupon!(portfolio)
    clear_coupon_securities!(portfolio)
    before = counts()
    assert before.transactions == 2

    again = apply!(@twin_coupons, "twin.json", portfolio)
    assert again.created_transactions == 0
    assert again.already_imported == %{hash: 2, retired: 0, economics: 1}
    assert counts() == before
  end

  # The state an import before the amendment left: the second coupon
  # collapsed onto the first, so no booking holds it (a test actor for the
  # journal guard).
  defp collapse_second_coupon!(portfolio) do
    larkspur = Enum.find(Catalog.list_securities(), &(&1.isin == "XSLARKSPUR33"))

    {:ok, _removed} =
      Repo.transaction(fn ->
        Repo.query!("SELECT set_config('portfolixir.journal_actor', 'test', true)")

        from(t in Transaction,
          where:
            t.portfolio_id == ^portfolio.id and t.type == "interest" and
              t.security_id == ^larkspur.id
        )
        |> Repo.delete_all()
      end)

    :ok
  end
end
