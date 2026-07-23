defmodule Portfolixir.Portfolios.Reconcile do
  @moduledoc """
  The FR-35 read-only holdings reconcile engine (ADR-0029 §6).

  Compares a user-supplied external position list (rows of `identifier` +
  `quantity`, optional `currency`, optional pinning `security_id`) against the
  ledger-derived holdings, matching each row through the ADR-0029 §2
  stable-identity ladder — the same semantics the import uses
  (`Portfolixir.Imports.SecurityResolver`), not a second one.

  Identifier typing, binding per §6:

    * a string that validates as an ISIN (format **and** check digit) enters
      tier 1 only — current ISINs first, then the §3 former-ISIN aliases; a
      tier-1 miss is `unmatched`, never a fall-through;
    * anything else is tried against the remaining tiers in ladder order with
      the exactly-one rule applied **across the union** of those tiers: a
      string matching one security's WKN and another's ticker is `ambiguous`
      with candidates, never a pick;
    * a currency-less row cannot enter the currency-qualified tiers 3–4 and is
      reported `unmatched` (`:currency_required`) rather than guessed;
    * an explicit `security_id` pins the match (`:pinned`) without consulting
      the ladder; an unknown pin is surfaced (`:unknown_security_id`).

  Rows resolving to the same security are aggregated (external quantities
  summed, the contributing rows listed), deltas are Decimal-exact
  (`delta = external - ledger`), tier-3/4 matches carry the weak-match caveat,
  and both unmatched external rows and held ledger positions absent from the
  list are surfaced (FR-7). The compare is bounded by an optional portfolio or
  view scope (default: the whole instance) and the result states its basis.

  Boundary (NFR-4): the module is **read-only** — `compute/3` is pure, and the
  `run/2` shell only loads (resolver index, ledger positions). Nothing from
  the external list is persisted or logged.
  """

  alias Portfolixir.Buckets
  alias Portfolixir.Imports.SecurityResolver
  alias Portfolixir.Imports.SecurityResolver.Index
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @zero Decimal.new("0")

  @guidance "resolve a difference by booking the missing transaction of the correct kind; " <>
              "balance snapshots and unpriced deliveries are last resorts that distort cost basis"

  @weak_match_caveat "confirm the security before booking"

  # Strength order for reporting the matched tier of an aggregated row: the
  # ladder tiers by rank, with an explicit pin between the exact-identifier
  # tiers and the weak (confirm-before-booking) tiers.
  @tier_rank %{isin: 0, former_isin: 1, wkn: 2, pinned: 3, ticker: 4, name: 5}
  @weak_tiers [:ticker, :name]

  @isin_format ~r/^[A-Z]{2}[A-Z0-9]{9}[0-9]$/

  @type row :: %{
          identifier: String.t(),
          quantity: Decimal.t(),
          currency: String.t() | nil,
          security_id: pos_integer() | nil
        }

  @doc "The embedded resolution guidance, verbatim per ADR-0029 §6."
  @spec guidance() :: String.t()
  def guidance, do: @guidance

  @doc "The weak-match caveat carried by tier-3/4 matches."
  @spec weak_match_caveat() :: String.t()
  def weak_match_caveat, do: @weak_match_caveat

  @doc """
  Loading shell: reads the resolver index and the in-scope ledger quantities,
  then delegates to the pure `compute/3`. Options: `:portfolio_id` or `:view`
  (a view id) to bound the compare; default is the whole instance.
  """
  @spec run([row()], keyword()) :: map()
  def run(rows, opts \\ []) when is_list(rows) do
    index = SecurityResolver.load_index()
    basis = basis(opts)
    positions = positions_for(basis)

    compute(rows, index, %{positions: positions, basis: basis})
  end

  defp basis(opts) do
    {scope, portfolio_id, view_id} =
      case {Keyword.get(opts, :portfolio_id), Keyword.get(opts, :view)} do
        {nil, nil} -> {:instance, nil, nil}
        {portfolio_id, nil} -> {:portfolio, portfolio_id, nil}
        {nil, view_id} -> {:view, nil, view_id}
      end

    %{
      as_of: Date.utc_today(),
      scope: scope,
      portfolio_id: portfolio_id,
      view_id: view_id,
      note:
        "Ledger quantities are derived on read from the transactions in scope, " <>
          "in security units; delta = external_quantity - ledger_quantity " <>
          "(positive: the external list shows more than the ledger)."
    }
  end

  # In-scope held quantity per security. All three paths are reads over the
  # public Ledger projections — nothing is written or cached.
  defp positions_for(%{scope: :instance}), do: Ledger.positions_by_security()

  defp positions_for(%{scope: :portfolio, portfolio_id: portfolio_id}) do
    portfolio_id
    |> Ledger.positions_for_portfolio()
    |> sum_by_security()
  end

  defp positions_for(%{scope: :view, view_id: view_id}) do
    scope = Buckets.load_global_scope(view_id)

    Portfolios.list_portfolios()
    |> Enum.flat_map(fn portfolio ->
      portfolio.id
      |> Ledger.positions_for_portfolio()
      |> Enum.filter(fn {{account_id, security_id}, _quantity} ->
        Buckets.position_in_scope?(scope, account_id, security_id)
      end)
    end)
    |> sum_by_security()
  end

  defp sum_by_security(positions) do
    Enum.reduce(positions, %{}, fn {{_account_id, security_id}, quantity}, acc ->
      Map.update(acc, security_id, quantity, &Decimal.add(&1, quantity))
    end)
  end

  @doc """
  Pure reconcile core: classifies every row against the prepared resolver
  `index`, aggregates rows resolving to the same security, computes exact
  Decimal deltas against `positions` (`%{security_id => Decimal}`), and
  surfaces unmatched rows plus held positions absent from the list.
  """
  @spec compute([row()], Index.t(), %{positions: map(), basis: map()}) :: map()
  def compute(rows, %Index{} = index, %{positions: positions, basis: basis}) do
    outcomes =
      rows
      |> Enum.with_index()
      |> Enum.map(fn {row, row_index} -> classify(row, row_index, index) end)

    matched = matched_rows(outcomes, positions)
    ambiguous = for {:ambiguous, entry} <- outcomes, do: entry
    unmatched = for {:unmatched, entry} <- outcomes, do: entry

    %{
      basis: basis,
      guidance: @guidance,
      matched: matched,
      ambiguous: ambiguous,
      unmatched: unmatched,
      missing_from_list: missing_from_list(positions, matched, ambiguous, index)
    }
  end

  # -- Per-row classification -------------------------------------------------

  defp classify(%{security_id: security_id} = row, row_index, index)
       when is_integer(security_id) do
    case Map.fetch(index.securities_by_id, security_id) do
      {:ok, security} -> {:match, security, :pinned, row, row_index}
      :error -> {:unmatched, unmatched_entry(row, row_index, :unknown_security_id)}
    end
  end

  defp classify(row, row_index, index) do
    code = normalize_code(row.identifier)

    if isin?(code) do
      isin_lookup(code, row, row_index, index)
    else
      union_lookup(row, row_index, index)
    end
  end

  # Tier 1 only, per §6: current ISINs first, then the §3 aliases; a miss is
  # unmatched — an ISIN-shaped identifier never tries the weaker tiers.
  defp isin_lookup(code, row, row_index, index) do
    case {Map.fetch(index.by_isin, code), Map.fetch(index.by_former_isin, code)} do
      {{:ok, security}, _} -> {:match, security, :isin, row, row_index}
      {:error, {:ok, security}} -> {:match, security, :former_isin, row, row_index}
      {:error, :error} -> {:unmatched, unmatched_entry(row, row_index, :no_match)}
    end
  end

  # Exactly-one across the union of the remaining tiers (§6): candidates from
  # WKN, (ticker, currency) and (name, currency) — each in the catalog normal
  # form the resolver index is built with — merged by security.
  defp union_lookup(row, row_index, index) do
    code = normalize_code(row.identifier)
    name = normalize_name(row.identifier)
    currency = normalize_code(row.currency)

    tier_hits =
      [
        {:wkn, Map.get(index.by_wkn, code, [])},
        {:ticker, currency_tier(index.by_ticker_ccy, code, currency)},
        {:name, currency_tier(index.by_name_ccy, name, currency)}
      ]
      |> Enum.reject(fn {_tier, candidates} -> candidates == [] end)

    candidates =
      tier_hits
      |> Enum.flat_map(fn {tier, securities} -> Enum.map(securities, &{&1, tier}) end)
      |> Enum.uniq_by(fn {security, _tier} -> security.id end)

    case candidates do
      [{security, tier}] ->
        {:match, security, tier, row, row_index}

      [] ->
        reason = if is_nil(currency), do: :currency_required, else: :no_match
        {:unmatched, unmatched_entry(row, row_index, reason)}

      many ->
        {:ambiguous,
         %{
           identifier: row.identifier,
           quantity: row.quantity,
           currency: row.currency,
           row_index: row_index,
           candidates: Enum.map(many, fn {security, _tier} -> security end)
         }}
    end
  end

  defp currency_tier(_map, _key, nil), do: []
  defp currency_tier(_map, nil, _currency), do: []
  defp currency_tier(map, key, currency), do: Map.get(map, {key, currency}, [])

  defp unmatched_entry(row, row_index, reason) do
    %{
      identifier: row.identifier,
      quantity: row.quantity,
      currency: row.currency,
      row_index: row_index,
      reason: reason
    }
  end

  # -- Aggregation and deltas -------------------------------------------------

  # One result row per matched security (§6: an agent never sees two
  # contradictory deltas for one position): external quantities summed, the
  # contributing rows listed, matched_via the strongest contributing tier.
  defp matched_rows(outcomes, positions) do
    outcomes
    |> Enum.flat_map(fn
      {:match, security, tier, row, row_index} -> [{security, tier, row, row_index}]
      _other -> []
    end)
    |> Enum.group_by(fn {security, _tier, _row, _row_index} -> security.id end)
    |> Enum.map(fn {security_id, group} -> matched_row(security_id, group, positions) end)
    |> Enum.sort_by(& &1.security.id)
  end

  defp matched_row(security_id, group, positions) do
    [{security, _, _, _} | _] = group
    matched_via = group |> Enum.map(&elem(&1, 1)) |> Enum.min_by(&Map.fetch!(@tier_rank, &1))
    weak_match = matched_via in @weak_tiers

    external =
      Enum.reduce(group, @zero, fn {_security, _tier, row, _row_index}, acc ->
        Decimal.add(acc, row.quantity)
      end)

    ledger = Map.get(positions, security_id, @zero)

    %{
      security: security,
      matched_via: matched_via,
      weak_match: weak_match,
      caveat: if(weak_match, do: @weak_match_caveat),
      ledger_quantity: ledger,
      external_quantity: external,
      delta: Decimal.sub(external, ledger),
      aggregated: length(group) > 1,
      rows:
        group
        |> Enum.map(fn {_security, tier, row, row_index} ->
          %{
            index: row_index,
            identifier: row.identifier,
            quantity: row.quantity,
            matched_via: tier
          }
        end)
        |> Enum.sort_by(& &1.index)
    }
  end

  # FR-7: held positions the external list does not cover. Securities already
  # surfaced as candidates of an ambiguous row are excluded — they are visible
  # as a pending decision, not silently absent.
  defp missing_from_list(positions, matched, ambiguous, index) do
    covered =
      MapSet.new(
        Enum.map(matched, & &1.security.id) ++
          Enum.flat_map(ambiguous, fn entry -> Enum.map(entry.candidates, & &1.id) end)
      )

    positions
    |> Enum.reject(fn {security_id, quantity} ->
      MapSet.member?(covered, security_id) or Decimal.eq?(quantity, @zero)
    end)
    |> Enum.map(fn {security_id, quantity} ->
      %{
        security: Map.get(index.securities_by_id, security_id),
        ledger_quantity: quantity
      }
    end)
    |> Enum.sort_by(fn %{security: security} -> security && security.name end)
  end

  # -- Identifier typing ------------------------------------------------------

  @doc """
  Whether a (normalized) string validates as an ISIN: two letters, nine
  alphanumerics, one check digit — verified with the ISO 6166 Luhn check over
  the digitized string. Only such strings enter tier 1 (§6).
  """
  @spec isin?(String.t() | nil) :: boolean()
  def isin?(value) when is_binary(value) do
    Regex.match?(@isin_format, value) and luhn_valid?(value)
  end

  def isin?(_value), do: false

  defp luhn_valid?(value) do
    value
    |> String.to_charlist()
    |> Enum.flat_map(&digitize/1)
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.reduce(0, fn {digit, position}, sum -> sum + luhn_digit(digit, position) end)
    |> rem(10) == 0
  end

  # A letter contributes its two-digit base-36 value (A=10 … Z=35).
  defp digitize(char) when char in ?0..?9, do: [char - ?0]
  defp digitize(char) when char in ?A..?Z, do: [div(char - ?A + 10, 10), rem(char - ?A + 10, 10)]

  defp luhn_digit(digit, position) when rem(position, 2) == 1 do
    doubled = digit * 2
    if doubled > 9, do: doubled - 9, else: doubled
  end

  defp luhn_digit(digit, _position), do: digit

  # Catalog normal form, mirroring the resolver: trimmed/upcased codes,
  # trimmed names, blanks to nil.
  defp normalize_code(value) when is_binary(value) do
    case value |> String.trim() |> String.upcase() do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_code(_value), do: nil

  defp normalize_name(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_name(_value), do: nil
end
