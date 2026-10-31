defmodule Portfolixir.LockRace.IsinWriteLockTest do
  # The ISIN write lock, one per normalized ISIN (security review 2026-10-12,
  # H53; ADR-0029 §3's serialized check), raced on two real connections by
  # the lock-order harness (#996). A writer takes the lock of every ISIN it
  # writes before any row lock, in ascending key order, so two writers of
  # the same ISINs queue on the first one both want and never wait on each
  # other crosswise. The importer takes the lock of every ISIN its file
  # names right after the portfolio's account-identity lock, once (#1287),
  # not row by row as it creates each security.
  #
  # The table of every writer's lock order is `Portfolixir.LockTable`.
  #
  # async: false -- the races share a scratch database and the barrier's
  # limits, and need no other test's load on the cores.
  #
  # Every name, figure and identifier is synthetic.
  use ExUnit.Case, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.IdentifierAliases
  alias Portfolixir.Catalog.Isin
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier.Result
  alias Portfolixir.LockRace
  alias Portfolixir.Portfolios
  alias Portfolixir.Repo

  @moduletag :lock_race

  setup_all do
    %{db: LockRace.database!()}
  end

  setup %{db: db} do
    Repo.put_dynamic_repo(db.repo)
    :ok
  end

  # User story (security review 2026-10-12, H53; #1287):
  # As the operator whose agent imports one export into one portfolio while
  # I import another into a second portfolio, both bringing the same two
  # securities new to the catalog in opposite file order,
  # I want the two imports to take the ISIN write locks in one order,
  # so that one waits for the other and neither is aborted by a deadlock.
  #
  # Acceptance criteria:
  # - The first import held right after its first ISIN write lock, the
  #   second run into it: the second waits for the first, and neither
  #   deadlocks (the importer takes the lock of every ISIN of its file
  #   right after the account-identity lock, in ascending key order; taken
  #   row by row, as it creates each security, the two closed a cycle).
  # - The first import creates both securities and books both rows; the
  #   second, which reads them once the first committed, books both rows
  #   onto them and creates none.
  test "two imports creating the same two ISINs in opposite orders do not deadlock",
       %{db: db} do
    first = portfolio!("Synthetic Import One")
    second = portfolio!("Synthetic Import Two")
    a = %{"name" => "Synthetic Fund A", "isin" => isin("XD", 1), "currency" => "EUR"}
    b = %{"name" => "Synthetic Fund B", "isin" => isin("XD", 2), "currency" => "EUR"}

    one = parse!([buy("One", "2026-02-02", a), buy("One", "2026-02-03", b)])
    two = parse!([buy("Two", "2026-02-02", b), buy("Two", "2026-02-03", a)])

    {first_result, second_result} =
      LockRace.race!(
        db,
        {fn -> Imports.apply(one, %{portfolio_id: first.id}) end, isin_write_lock?()},
        fn -> Imports.apply(two, %{portfolio_id: second.id}) end
      )

    assert {:ok, %Result{created_securities: 2, created_transactions: 2}} = first_result
    assert {:ok, %Result{created_securities: 0, created_transactions: 2}} = second_result
  end

  # User story (#1287):
  # As the operator recording an ISIN change of a security while an import
  # books that security and creates another,
  # I want the import to hold the ISIN write locks before it books any row,
  # so that the ISIN change waits for the import, or the import for it, and
  # neither is aborted by a deadlock.
  #
  # Acceptance criteria:
  # - The import of a file that buys the stored security X, then a security
  #   Y new to the catalog, held after its first booking (which holds X's
  #   row in key share); an ISIN change of X onto Y's ISIN run into it: the
  #   change waits for the import, and neither deadlocks (taken when the
  #   import created Y, the ISIN lock closed a cycle with the change, which
  #   holds it and waits for X's row).
  # - The import books both rows and creates Y; the change, which finds Y's
  #   ISIN live on Y once the import committed, is refused, and X keeps its
  #   ISIN.
  test "an ISIN change waits for an import that books its security and creates another",
       %{db: db} do
    portfolio = portfolio!("Synthetic ISIN Change One")
    x = security!("Synthetic Stored X", isin("XE", 1))
    y_isin = isin("XE", 2)
    y = %{"name" => "Synthetic New Y", "isin" => y_isin, "currency" => "EUR"}

    file = parse!([buy("Three", "2026-03-02", ref(x)), buy("Three", "2026-03-03", y)])

    {imported, changed} =
      LockRace.race!(
        db,
        {fn -> Imports.apply(file, %{portfolio_id: portfolio.id}) end,
         LockRace.query?(~s(INSERT INTO "transactions"))},
        fn -> Catalog.record_isin_change(Actor.owner_ui(), x, y_isin) end
      )

    assert {:ok, %Result{created_securities: 1, created_transactions: 2}} = imported
    assert {:error, %Ecto.Changeset{}} = changed
    assert Repo.get!(Security, x.id).isin == x.isin
  end

  # Acceptance criteria (#1287, the other order):
  # - The ISIN change of X onto a new ISIN held after it locked X's row; the
  #   import of a file that buys X under its old ISIN and under the new one
  #   run into it: the import waits for the change at the ISIN write locks,
  #   before it books any row, and neither deadlocks.
  # - The change lands. The import, which reads the catalog once it holds
  #   the locks, finds X under its new ISIN and under the old one (now a
  #   former ISIN), books both rows onto X and creates no security.
  test "an import waits at the ISIN write locks for an ISIN change of a security it books",
       %{db: db} do
    portfolio = portfolio!("Synthetic ISIN Change Two")
    x = security!("Synthetic Stored Z", isin("XE", 3))
    new_isin = isin("XE", 4)
    renamed = %{"name" => "Synthetic Stored Z", "isin" => new_isin, "currency" => "EUR"}

    file = parse!([buy("Four", "2026-03-02", ref(x)), buy("Four", "2026-03-03", renamed)])

    {changed, imported} =
      LockRace.race!(
        db,
        {fn -> Catalog.record_isin_change(Actor.owner_ui(), x, new_isin) end,
         LockRace.query?("FOR UPDATE")},
        fn -> Imports.apply(file, %{portfolio_id: portfolio.id}) end
      )

    assert {:ok, %{security: %{isin: ^new_isin}}} = changed
    assert {:ok, %Result{created_securities: 0, created_transactions: 2}} = imported
  end

  # User story (security review 2026-10-12, H53):
  # As the operator correcting a security's ISIN while an ISIN change of the
  # same security onto another ISIN is recorded,
  # I want the two writers to queue on the security's own key of the ISIN
  # write lock,
  # so that each replaces the ISIN it locked, never one the other has just
  # written.
  #
  # Acceptance criteria:
  # - The security stored under ISIN A; an ISIN change onto B, whose key
  #   sorts before A's, held after its first ISIN write lock; an ISIN edit
  #   onto C run into it: the edit waits for the change, though the two
  #   share no ISIN but the stored one, whose lock the change, holding the
  #   security's key, has not yet taken. (Mutation: without the security's
  #   key the change's first lock is B's, and the edit, locking A and C,
  #   passes it and writes over a stored ISIN the change is replacing.)
  # - Both land in order: the change records A as a former ISIN, and the
  #   edit then writes C over B.
  test "an ISIN edit waits on the security's key for an ISIN change of it", %{db: db} do
    a = isin("XK", 1)
    b = isin_keyed_before(a)
    c = isin("XK", 900)
    security = security!("Synthetic Keyed AG", a)

    {changed, edited} =
      LockRace.race!(
        db,
        {fn -> Catalog.record_isin_change(Actor.owner_ui(), security, b) end, isin_write_lock?()},
        fn -> Catalog.update_security(Actor.owner_ui(), security, %{isin: c}) end
      )

    assert {:ok, %{security: %{isin: ^b}, alias: %{former_isin: ^a}}} = changed
    assert {:ok, %Security{isin: ^c}} = edited
    assert Repo.get!(Security, security.id).isin == c
  end

  # --- the world ---------------------------------------------------------------------

  # A synthetic ISIN whose write-lock key, in the database-wide scope the
  # races run under, sorts before `isin`'s.
  defp isin_keyed_before(isin) do
    key = &IdentifierAliases.lock_key_for("0", &1)

    Enum.find_value(2..500, fn n ->
      candidate = isin("XK", n)
      if key.(candidate) < key.(isin), do: candidate
    end)
  end

  # A pause predicate: the writer's first ISIN write lock.
  defp isin_write_lock? do
    key = IdentifierAliases.isin_write_lock_key()

    fn
      %{query: query, params: [^key | _]} when is_binary(query) ->
        String.contains?(query, "pg_advisory_xact_lock")

      _metadata ->
        false
    end
  end

  defp portfolio!(name) do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: name, base_currency_code: "EUR"})

    portfolio
  end

  defp security!(name, isin) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{name: name, isin: isin, currency_code: "EUR"})

    security
  end

  defp ref(%Security{} = security),
    do: %{"name" => security.name, "isin" => security.isin, "currency" => "EUR"}

  # A synthetic ISIN with a valid check digit.
  defp isin(prefix, n) do
    base = prefix <> String.pad_leading(Integer.to_string(n), 9, "0")
    Enum.find_value(0..9, fn d -> if Isin.valid?(base <> "#{d}"), do: base <> "#{d}" end)
  end

  defp num(digits), do: Jason.Fragment.new(digits)

  defp buy(prefix, date, security) do
    %{
      "type" => "PURCHASE",
      "account" => "#{prefix} Synthetic Cash",
      "portfolio" => "#{prefix} Synthetic Depot",
      "date" => date,
      "time" => "10:00",
      "currency" => "EUR",
      "amount" => num("100.00"),
      "shares" => num("1"),
      "security" => security
    }
  end

  defp parse!(rows) do
    body = Jason.encode!(%{"version" => 1, "transactions" => rows})
    {:ok, preview} = Imports.parse_portfolio_performance(body, filename: "synthetic.json")
    preview
  end
end
