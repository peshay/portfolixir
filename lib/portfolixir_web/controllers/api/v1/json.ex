defmodule PortfolixirWeb.Api.V1.JSON do
  @moduledoc false

  alias Ecto.Changeset
  alias Portfolixir.Buckets.Bucket
  alias Portfolixir.Buckets.View
  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Catalog.SecuritySearch.SearchResult
  alias Portfolixir.Classifications.Assignment
  alias Portfolixir.Classifications.Category
  alias Portfolixir.Classifications.Classification
  alias Portfolixir.Fx.ExchangeRate
  alias Portfolixir.Journal.Entry, as: JournalEntry
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.{CashAccount, Portfolio, SecuritiesAccount, Target}
  alias Portfolixir.Portfolios.Snapshot
  alias Portfolixir.Portfolios.TargetPlan

  # Slim listing projection (FR-33): a FIXED whitelist for routine listings so
  # notes, feed config, attributes and timestamps don't ride along on every
  # page an LLM operator requests. Deliberately not a generic field selector —
  # scope-locked to the securities list; `?view=full` returns `security/1`.
  def security_listing(%Security{} = security) do
    %{
      id: security.id,
      name: security.name,
      ticker_symbol: security.ticker_symbol,
      isin: security.isin,
      wkn: security.wkn,
      currency_code: security.currency_code,
      asset_class: security.asset_class
    }
  end

  def security(%Security{} = security) do
    %{
      id: security.id,
      name: security.name,
      ticker_symbol: security.ticker_symbol,
      isin: security.isin,
      wkn: security.wkn,
      currency_code: security.currency_code,
      exchange_code: security.exchange_code,
      asset_class: security.asset_class,
      note: security.note,
      feed: security.feed,
      feed_url: security.feed_url,
      latest_feed: security.latest_feed,
      latest_feed_url: security.latest_feed_url,
      is_retired: security.is_retired,
      online_id: security.online_id,
      provider: security.provider,
      attributes: security.attributes || %{},
      inserted_at: timestamp(security.inserted_at),
      updated_at: timestamp(security.updated_at)
    }
  end

  def logo_status(%Security{} = security) do
    status = Portfolixir.Catalog.logo_status(security)

    %{
      security_id: security.id,
      path: status.path,
      source: status.source,
      has_logo: status.has_logo,
      locked: status.locked
    }
  end

  def search_result(%SearchResult{} = result) do
    %{
      provider: provider(result.provider),
      online_id: result.online_id,
      name: result.name,
      isin: result.isin,
      wkn: result.wkn,
      ticker_symbol: result.ticker_symbol,
      asset_class: result.asset_class,
      currency_code: result.currency_code,
      feed: result.feed,
      markets: Enum.map(result.markets || [], &market/1),
      raw: result.raw || %{}
    }
  end

  def portfolio(%Portfolio{} = portfolio) do
    %{
      id: portfolio.id,
      name: portfolio.name,
      base_currency_code: portfolio.base_currency_code,
      notes: portfolio.notes,
      cash_target_weight: decimal(portfolio.cash_target_weight),
      inserted_at: timestamp(portfolio.inserted_at),
      updated_at: timestamp(portfolio.updated_at)
    }
  end

  def cash_account(%CashAccount{} = account) do
    %{
      id: account.id,
      portfolio_id: account.portfolio_id,
      name: account.name,
      currency_code: account.currency_code,
      notes: account.notes,
      liquidity_role: account.liquidity_role,
      inserted_at: timestamp(account.inserted_at),
      updated_at: timestamp(account.updated_at)
    }
  end

  def securities_account(%SecuritiesAccount{} = account) do
    cash_account =
      case Ecto.assoc_loaded?(account.cash_account) do
        true -> cash_account(account.cash_account)
        false -> nil
      end

    %{
      id: account.id,
      portfolio_id: account.portfolio_id,
      cash_account_id: account.cash_account_id,
      name: account.name,
      notes: account.notes,
      cash_account: cash_account,
      inserted_at: timestamp(account.inserted_at),
      updated_at: timestamp(account.updated_at)
    }
  end

  def transaction(%Transaction{} = transaction) do
    %{
      id: transaction.id,
      portfolio_id: transaction.portfolio_id,
      securities_account_id: transaction.securities_account_id,
      cash_account_id: transaction.cash_account_id,
      counter_cash_account_id: transaction.counter_cash_account_id,
      counter_securities_account_id: transaction.counter_securities_account_id,
      security_id: transaction.security_id,
      type: transaction.type,
      date: date(transaction.date),
      quantity: decimal(transaction.quantity),
      price: decimal(transaction.price),
      gross_amount: decimal(transaction.gross_amount),
      fees: decimal(transaction.fees),
      taxes: decimal(transaction.taxes),
      currency_code: transaction.currency_code,
      security_amount: decimal(transaction.security_amount),
      settlement_amount: decimal(transaction.settlement_amount),
      settlement_fx_rate: decimal(transaction.settlement_fx_rate),
      notes: transaction.notes,
      import_hash: transaction.import_hash,
      inserted_at: timestamp(transaction.inserted_at),
      updated_at: timestamp(transaction.updated_at)
    }
  end

  def trades(%{open_lots: lots, closed_trades: closed, orphan_sells: orphans}) do
    %{
      # FR-13: state the matching method so a consumer never has to assume how
      # lots were paired against sells. Trades are matched first-in, first-out.
      method: "fifo",
      open_lots: Enum.map(lots, &open_lot/1),
      closed_trades: Enum.map(closed, &closed_trade/1),
      orphan_sells: Enum.map(orphans, &orphan_sell/1)
    }
  end

  defp open_lot(lot) do
    %{
      open_date: date(lot.open_date),
      quantity: decimal(lot.quantity),
      original_quantity: decimal(lot.original_quantity),
      buy_price: decimal(lot.buy_price),
      buy_fees: decimal(lot.buy_fees),
      buy_taxes: decimal(lot.buy_taxes),
      latest_price: decimal(lot.latest_price),
      unrealized_pnl_abs: decimal(lot.unrealized_pnl_abs),
      unrealized_pnl_pct: decimal(lot.unrealized_pnl_pct),
      currency_code: lot.currency_code
    }
  end

  defp closed_trade(trade) do
    %{
      open_date: date(trade.open_date),
      close_date: date(trade.close_date),
      quantity: decimal(trade.quantity),
      avg_buy_price: decimal(trade.avg_buy_price),
      avg_sell_price: decimal(trade.avg_sell_price),
      buy_fees: decimal(trade.buy_fees),
      buy_taxes: decimal(trade.buy_taxes),
      sell_fees: decimal(trade.sell_fees),
      sell_taxes: decimal(trade.sell_taxes),
      basis: decimal(trade.basis),
      proceeds: decimal(trade.proceeds),
      realized_pnl_abs: decimal(trade.realized_pnl_abs),
      realized_pnl_pct: decimal(trade.realized_pnl_pct),
      holding_period_days: trade.holding_period_days,
      currency_code: trade.currency_code
    }
  end

  defp orphan_sell(orphan) do
    %{
      date: date(orphan.date),
      quantity: decimal(orphan.quantity),
      price: decimal(orphan.price),
      currency_code: orphan.currency_code
    }
  end

  def quote(%SecurityQuote{} = quote) do
    %{
      id: quote.id,
      security_id: quote.security_id,
      date: date(quote.date),
      close: decimal(quote.close),
      source: quote.source,
      inserted_at: timestamp(quote.inserted_at),
      updated_at: timestamp(quote.updated_at)
    }
  end

  def holdings(holdings, portfolio_id) when is_list(holdings) do
    %{
      # FR-13: state the currency basis and read date so a consumer knows the
      # rows carry no FX conversion (see the valuation for base-currency totals).
      # There is no stored snapshot, so `as_of` documents the read date.
      currency_basis: "security_currency",
      as_of: date(Date.utc_today()),
      data: Enum.map(holdings, &holding(&1, portfolio_id))
    }
  end

  def holding(holding, portfolio_id) do
    %{
      portfolio_id: portfolio_id,
      securities_account_id: holding.securities_account_id,
      security_id: holding.security_id,
      security_name: holding.security_name,
      isin: holding.isin,
      wkn: holding.wkn,
      currency_code: holding.currency_code,
      quantity: decimal(holding.quantity),
      avg_cost: decimal(holding.avg_cost),
      cost_basis: decimal(holding.cost_basis),
      latest_price: decimal(holding.latest_price),
      market_value: decimal(holding.market_value),
      unrealized_pnl_abs: decimal(holding.unrealized_pnl_abs),
      unrealized_pnl_pct: decimal(holding.unrealized_pnl_pct)
    }
  end

  def holdings_by_security(%{holdings: holdings} = report) do
    %{
      currency: report.currency,
      as_of: date(report.as_of),
      note: report.note,
      holdings: Enum.map(holdings, &holdings_by_security_row/1)
    }
  end

  defp holdings_by_security_row(row) do
    %{
      security_id: row.security_id,
      quantity: decimal(row.quantity),
      market_value: decimal(row.market_value),
      valued: row.valued
    }
  end

  def valuation(%{positions: positions} = valuation) do
    %{
      portfolio_id: valuation.portfolio_id,
      base_currency: valuation.base_currency,
      # FR-13: describe the read date and the chosen basis so a consumer never
      # has to assume how totals were built. There is no stored snapshot, so
      # `as_of` documents the read date (mirrors the income report).
      as_of: date(Date.utc_today()),
      valuation_note: valuation_note(valuation.base_currency),
      total_value: decimal(valuation.total_value),
      total_cash: decimal(valuation.total_cash),
      counting_cash: decimal(valuation.counting_cash),
      total_with_cash: decimal(valuation.total_with_cash),
      cash_quote: decimal(valuation.cash_quote),
      unvalued_count: valuation.unvalued_count,
      trade_priced_count: valuation.trade_priced_count,
      positions: Enum.map(positions, &valuation_position/1),
      cash_balances: Enum.map(valuation.cash_balances, &valuation_cash/1)
    }
  end

  defp valuation_note(base_currency) do
    "Totals are in #{base_currency} (base_currency), converted via the EUR " <>
      "hub at each position's stored rate; `price_source` and `valued` " <>
      "indicate per-position price staleness."
  end

  @doc """
  Serializes the cross-portfolio view valuation (ADR-0024): the `for_portfolio`
  shape with `view_id` in place of `portfolio_id`, plus account-level `overlap`
  data (which depots/cash accounts carry more than one of the view's included
  buckets — badge data; the totals are already deduplicated).
  """
  def view_valuation(%{positions: positions} = valuation) do
    %{
      view_id: valuation.view_id,
      base_currency: valuation.base_currency,
      # FR-13: `as_of` documents the read date (no stored snapshot exists) and
      # the note states the cross-portfolio, count-once basis of the totals.
      as_of: date(Date.utc_today()),
      valuation_note: view_valuation_note(valuation.base_currency),
      total_value: decimal(valuation.total_value),
      total_cash: decimal(valuation.total_cash),
      counting_cash: decimal(valuation.counting_cash),
      total_with_cash: decimal(valuation.total_with_cash),
      cash_quote: decimal(valuation.cash_quote),
      unvalued_count: valuation.unvalued_count,
      trade_priced_count: valuation.trade_priced_count,
      overlap: view_overlap(valuation.overlap),
      # Whether the view's resolution matches no account at all (fix round):
      # clients can hint "matches no accounts" instead of a silent 0 total.
      matches_no_accounts: Map.get(valuation, :matches_no_accounts, false),
      positions: Enum.map(positions, &valuation_position/1),
      cash_balances: Enum.map(valuation.cash_balances, &valuation_cash/1)
    }
  end

  defp view_valuation_note(base_currency) do
    "Totals are in #{base_currency} across ALL portfolios, converted via the " <>
      "EUR hub; each account matching the view counts exactly once, however " <>
      "many included buckets it carries (`overlap` lists the multi-bucket " <>
      "accounts). `price_source` and `valued` indicate per-position price " <>
      "staleness."
  end

  defp view_overlap(overlap) do
    %{
      overlapping: overlap.overlapping?,
      securities_account_ids: overlap.securities_account_ids,
      cash_account_ids: overlap.cash_account_ids
    }
  end

  defp valuation_cash(cash) do
    %{
      cash_account_id: cash.cash_account_id,
      name: cash.name,
      currency: cash.currency,
      balance: decimal(cash.balance),
      base_value: decimal(cash.base_value),
      valued: cash.valued,
      liquidity_role: cash.liquidity_role,
      deployable: cash.deployable
    }
  end

  defp valuation_position(position) do
    %{
      securities_account_id: position.securities_account_id,
      security_id: position.security_id,
      security_name: position.security_name,
      asset_class: position.asset_class,
      security_currency: position.security_currency,
      quantity: decimal(position.quantity),
      latest_price: decimal(position.latest_price),
      price_source: position.price_source,
      market_value: decimal(position.market_value),
      weight: decimal(position.weight),
      valued: position.valued
    }
  end

  def target(%Target{} = target) do
    %{
      portfolio_id: target.portfolio_id,
      classification_id: target.classification_id,
      category_id: target.category_id,
      target_weight: decimal(target.target_weight)
    }
  end

  @doc """
  The per-plan cash target (ADR-0020) as a Decimal string, or `nil` when none is
  steered. The cash target moved off the portfolio object onto the (view,
  classification) plan; this serializes the plan's cash target weight.
  """
  def cash_target(weight), do: %{cash_target_weight: decimal(weight)}

  @doc "A SOLL plan version (ADR-0027); the cash target weight as a string."
  def plan(%TargetPlan{} = plan) do
    %{
      id: plan.id,
      portfolio_id: plan.portfolio_id,
      view_id: plan.view_id,
      classification_id: plan.classification_id,
      name: plan.name,
      status: plan.status,
      cash_target_weight: decimal(plan.cash_target_weight)
    }
  end

  @doc "A depot snapshot marker (ADR-0027) — scope + as-of date, no values."
  def snapshot(%Snapshot{} = snapshot) do
    %{
      id: snapshot.id,
      name: snapshot.name,
      view_id: snapshot.view_id,
      as_of: Date.to_iso8601(snapshot.as_of)
    }
  end

  @doc """
  The counterfactual comparison (ADR-0027): buy-and-hold of the snapshot's
  frozen holdings vs. the scope's real TTWROR since the as-of date. All
  financial decimals as strings; self-describing via `basis` and explicit
  `gaps` (AR-4).
  """
  def snapshot_comparison(comparison) do
    %{
      snapshot: %{
        id: comparison.snapshot.id,
        name: comparison.snapshot.name,
        as_of: Date.to_iso8601(comparison.snapshot.as_of),
        view_id: comparison.snapshot.view_id
      },
      base_currency: comparison.base_currency,
      as_of: Date.to_iso8601(comparison.as_of),
      today: Date.to_iso8601(comparison.today),
      as_of_value: decimal(comparison.as_of_value),
      current_value: decimal(comparison.current_value),
      snapshot_return: decimal(comparison.snapshot_return),
      real_ttwror: decimal(comparison.real_ttwror),
      series:
        Enum.map(comparison.series, fn point ->
          %{
            date: Date.to_iso8601(point.date),
            snapshot_value: decimal(point.snapshot_value),
            snapshot_indexed: decimal(point.snapshot_indexed),
            real_indexed: decimal(point.real_indexed)
          }
        end),
      gaps: %{
        unvalued_securities:
          Enum.map(comparison.gaps.unvalued_securities, fn gap ->
            %{
              security_id: gap.security_id,
              security_name: gap.security_name,
              reason: gap.reason
            }
          end)
      },
      basis: comparison.basis
    }
  end

  def allocation(allocation) do
    %{
      portfolio_id: allocation.portfolio_id,
      classification_id: allocation.classification_id,
      classification_name: allocation.classification_name,
      base_currency: allocation.base_currency,
      total_value: decimal(allocation.total_value),
      unvalued_count: allocation.unvalued_count,
      categories: Enum.map(allocation.categories, &allocation_category/1),
      cash: allocation_cash(allocation.cash),
      top_level_target_sum: decimal(allocation.top_level_target_sum),
      unassigned: allocation_unassigned(allocation.unassigned)
    }
  end

  defp allocation_cash(cash) do
    %{
      market_value: decimal(cash.market_value),
      actual_weight: decimal(cash.actual_weight),
      target_weight: decimal(cash.target_weight),
      drift_weight: decimal(cash.drift_weight),
      drift_value: decimal(cash.drift_value),
      # true when cash is distributed into currency buckets (issue #407):
      # the currency classification attributes cash to its currency category,
      # so consumers should render no separate Cash row in that view.
      distributed: Map.get(cash, :distributed, false)
    }
  end

  defp allocation_category(category) do
    %{
      category_id: category.category_id,
      parent_id: category.parent_id,
      depth: category.depth,
      name: category.name,
      color: category.color,
      own_market_value: decimal(category.own_market_value),
      market_value: decimal(category.market_value),
      actual_weight: decimal(category.actual_weight),
      target_weight: decimal(category.target_weight),
      drift_weight: decimal(category.drift_weight),
      drift_value: decimal(category.drift_value),
      child_target_sum: decimal(category.child_target_sum),
      positions: Enum.map(category.positions, &allocation_position/1)
    }
  end

  # `drift_value` is the position's share of its category's drift and
  # `rebalance_quantity` the indicative quantity to sell (positive) or buy
  # (negative) at the implied unit price — display-only hints (ADR-0023), nil
  # without a plan and for `unassigned` positions.
  defp allocation_position(position) do
    %{
      security_id: position.security_id,
      security_name: position.security_name,
      quantity: decimal(position.quantity),
      market_value: decimal(position.market_value),
      weight: decimal(position.weight),
      drift_value: decimal(position.drift_value),
      rebalance_quantity: decimal(position.rebalance_quantity)
    }
  end

  defp allocation_unassigned(nil), do: nil

  defp allocation_unassigned(unassigned) do
    %{
      market_value: decimal(unassigned.market_value),
      actual_weight: decimal(unassigned.actual_weight),
      positions: Enum.map(unassigned.positions, &allocation_position/1)
    }
  end

  def risk(risk) do
    %{
      portfolio_id: risk.portfolio_id,
      base_currency: risk.base_currency,
      # FR-13: `as_of` documents the read date; the lens is derived on read from
      # the live valuation, so there is no stored snapshot date to report. The
      # note states the basis so a consumer never has to assume what the weights
      # and HHI are a share of.
      as_of: date(Date.utc_today()),
      risk_note: risk_note(),
      steerable_basis: decimal(risk.steerable_basis),
      top_holdings: Enum.map(risk.top_holdings, &risk_holding/1),
      hhi: risk_hhi(risk.hhi),
      asset_class_violations: Enum.map(risk.asset_class_violations, &risk_violation/1)
    }
  end

  defp risk_note do
    "Weights, caps and HHI are on a 0-100 percentage scale over the steerable " <>
      "basis (the valued positions, scoped by the active view); a security held " <>
      "across depots is merged into one single-name exposure."
  end

  defp risk_holding(holding) do
    %{
      security_id: holding.security_id,
      security_name: holding.security_name,
      asset_class: holding.asset_class,
      market_value: decimal(holding.market_value),
      weight: decimal(holding.weight),
      severity: holding.severity
    }
  end

  defp risk_hhi(hhi) do
    %{value: decimal(hhi.value), band: hhi.band}
  end

  defp risk_violation(violation) do
    %{
      asset_class: violation.asset_class,
      current_weight: decimal(violation.current_weight),
      cap: decimal(violation.cap),
      overage: decimal(violation.overage)
    }
  end

  def income(income) do
    %{
      portfolio_id: income.portfolio_id,
      base_currency: income.base_currency,
      conversion_note: income.conversion_note,
      unconverted_count: income.unconverted_count,
      annual: Enum.map(income.annual, &income_year/1),
      positions: Enum.map(income.positions, &income_position/1),
      transactions: Enum.map(income.transactions, &income_transaction/1)
    }
  end

  defp income_year(year) do
    %{
      year: year.year,
      dividends_total: decimal(year.dividends_total),
      interest_total: decimal(year.interest_total),
      total: decimal(year.total),
      months:
        Map.new(year.months, fn {month, series} ->
          {Integer.to_string(month),
           %{dividends: decimal(series.dividends), interest: decimal(series.interest)}}
        end)
    }
  end

  defp income_position(position) do
    %{
      security_id: position.security_id,
      security_name: position.security_name,
      security_currency: position.security_currency,
      gross: decimal(position.gross),
      tax: decimal(position.tax),
      net: decimal(position.net),
      payment_count: position.payment_count,
      last_payment: date(position.last_payment)
    }
  end

  defp income_transaction(transaction) do
    %{
      kind: transaction.kind,
      date: date(transaction.date),
      year: transaction.year,
      security_id: transaction.security_id,
      security_name: transaction.security_name,
      currency: transaction.currency,
      native_gross: decimal(transaction.native_gross),
      native_tax: decimal(transaction.native_tax),
      native_net: decimal(transaction.native_net),
      gross: decimal(transaction.gross),
      tax: decimal(transaction.tax),
      net: decimal(transaction.net),
      converted: transaction.converted
    }
  end

  def performance(result, include_series? \\ false) do
    base = %{
      portfolio_id: result.portfolio_id,
      period: result.period,
      base_currency: result.base_currency,
      start_date: date(result.start_date),
      end_date: date(result.end_date),
      start_value: decimal(result.start_value),
      end_value: decimal(result.end_value),
      net_external_flows: decimal(result.net_external_flows),
      ttwror: decimal(result.ttwror),
      irr: decimal(result.irr),
      suspect_dates: Enum.map(result.suspect_dates, &date/1)
    }

    if include_series? do
      Map.put(base, :series, Enum.map(result.series, &performance_point/1))
    else
      base
    end
  end

  defp performance_point(point) do
    %{
      date: date(point.date),
      value: decimal(point.value),
      flow: decimal(point.flow),
      cumulative_ttwror: decimal(point.cumulative_ttwror)
    }
  end

  def classification_tree(%{classification: classification} = tree) do
    classification
    |> classification()
    |> Map.merge(%{
      categories: Enum.map(tree.categories, &category/1),
      assignments: Enum.map(tree.assignments, &assignment/1)
    })
  end

  def classification(%Classification{} = classification) do
    %{
      id: classification.id,
      name: classification.name,
      key: classification.key,
      built_in: classification.built_in,
      position: classification.position,
      description: classification.description
    }
  end

  def category(%Category{} = category) do
    %{
      id: category.id,
      classification_id: category.classification_id,
      parent_id: category.parent_id,
      name: category.name,
      key: category.key,
      color: category.color,
      description: category.description,
      position: category.position
    }
  end

  def assignment(%Assignment{} = assignment) do
    %{
      security_id: assignment.security_id,
      classification_id: assignment.classification_id,
      category_id: assignment.category_id
    }
  end

  def assignment(%{security_id: security_id, category_id: category_id}) do
    %{security_id: security_id, category_id: category_id}
  end

  def exchange_rate(%ExchangeRate{} = rate) do
    %{
      base_currency: rate.base_currency,
      quote_currency: rate.quote_currency,
      date: date(rate.date),
      rate: decimal(rate.rate),
      source: rate.source
    }
  end

  def fx_sync_result(%{provider: provider, status: status, upserted: upserted}) do
    %{provider: to_string(provider), status: to_string(status), upserted: upserted}
  end

  def journal_entry(%JournalEntry{} = entry) do
    %{
      id: entry.id,
      actor_type: to_string(entry.actor_type),
      actor_label: entry.actor_label,
      operation: to_string(entry.operation),
      resource_type: entry.resource_type,
      resource_id: entry.resource_id,
      before: entry.before,
      after: entry.after,
      scenario_id: entry.scenario_id,
      inserted_at: datetime(entry.inserted_at)
    }
  end

  @doc """
  Serializes a bucket. `dimension` is `"tag"` (free overlapping tag) or
  `"scope"` (the exclusive dimension: at most one per account, ADR-0024) and
  is fixed at creation. The internal seed marker (`source_portfolio_id`) is
  deliberately not exposed.
  """
  def bucket(%Bucket{} = bucket) do
    %{
      id: bucket.id,
      name: bucket.name,
      color: bucket.color,
      dimension: bucket.dimension,
      inserted_at: timestamp(bucket.inserted_at),
      updated_at: timestamp(bucket.updated_at)
    }
  end

  @doc """
  Serializes a view with its resolved include/exclude bucket-id sets. `include`
  is the literal string `"all"` when the view includes every bucket
  (`include_all`), otherwise the list of included bucket ids; `exclude` is the
  list of excluded bucket ids (exclude wins).
  """
  def view(%View{} = view, %{include: include, exclude: exclude}) do
    %{
      id: view.id,
      name: view.name,
      include_all: view.include_all,
      include: view_include(include),
      exclude: exclude,
      inserted_at: timestamp(view.inserted_at),
      updated_at: timestamp(view.updated_at)
    }
  end

  defp view_include(:all), do: "all"
  defp view_include(ids) when is_list(ids), do: ids

  @doc "The active `view` scope echoed into a scoped analytics response (FR-13)."
  def active_view(%View{} = view), do: %{id: view.id, name: view.name}

  def errors(%Changeset{} = changeset) do
    Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  def decimal(nil), do: nil

  def decimal(%Decimal{} = decimal) do
    decimal
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end

  def decimal(value), do: to_string(value)

  def date(nil), do: nil
  def date(%Date{} = date), do: Date.to_iso8601(date)

  def timestamp(nil), do: nil
  def timestamp(%NaiveDateTime{} = timestamp), do: NaiveDateTime.to_iso8601(timestamp)

  def datetime(nil), do: nil
  def datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp provider(nil), do: nil
  defp provider(provider) when is_atom(provider), do: Atom.to_string(provider)
  defp provider(provider), do: to_string(provider)

  defp market(market) do
    %{
      symbol: market.symbol,
      currency_code: market.currency_code,
      exchange_code: market.exchange_code,
      exchange_name: market.exchange_name,
      url: market.url
    }
  end
end
