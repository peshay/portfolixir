defmodule Portfolixir.Catalog.SecurityCycles do
  @moduledoc """
  The halving cycles read of one security (FR-58,
  [ADR-0060](../../docs/decisions/0060-halving-cycles-tops-and-lows-by-drawdown-projected-as-a-band.md)
  §1 to §3, §9, §12): its past — the windows between its confirmed halvings,
  each window's top and low, and the six intervals with n, minimum and
  maximum.

  The **shell** half of the engine/shell split (AR-2), as
  `Portfolixir.Catalog.SecurityMetrics` is: it loads the security's
  split-adjusted closes (ADR-0028 §2) and its `halving` events (ADR-0048's
  amendment of 2026-11-12, ADR-0059), hands them to
  `Portfolixir.Engines.Cycles`, and wraps the answer in the computation basis
  the `AGENTS.md` metric rule requires **in the payload**.

  ## The series, and why it is not converted

  The security's own stored closes in its **own quote currency** (ADR-0060
  §1, ADR-0047 §1): converting would fold an FX path into a figure about the
  instrument, so a listing in EUR has EUR cycles and the basis names the
  currency. Positive closes only; a day without a close is skipped, never
  filled. The whole stored history up to today is read: the read takes no
  `as_of` (ADR-0060 §8), so nobody can compute a past cycle's view from that
  cycle's data.

  ## Computed at every read

  Nothing about a cycle is stored (ADR-0060 §10, ADR-0004): the same closes
  and halvings give the same answer, and a corrected close is followed by the
  next read.
  """

  import Ecto.Query

  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Clock
  alias Portfolixir.Engines.Cycles
  alias Portfolixir.Knowledge.SecurityEvent
  alias Portfolixir.Repo

  # Older than any stored quote: the read takes the whole history.
  @series_floor ~D[1900-01-01]

  @doc """
  `{:ok, payload}` for one security, or `{:error, :not_found}`.

  Where the view does not exist (ADR-0060 §1) the payload answers
  `cycles: []`, `intervals: nil` and a `reason`: `:no_halving_chain`
  (the security is bound to no chain), `:too_few_halvings` (fewer than two
  confirmed halvings), `:no_closes` (no close inside any window).
  """
  @spec for_security(integer() | String.t()) :: {:ok, map()} | {:error, :not_found}
  def for_security(security_id) when is_binary(security_id) do
    case Integer.parse(security_id) do
      {id, ""} -> for_security(id)
      _other -> {:error, :not_found}
    end
  end

  def for_security(security_id) when is_integer(security_id) do
    case Repo.get(Security, security_id) do
      nil -> {:error, :not_found}
      %Security{} = security -> {:ok, read(security)}
    end
  end

  defp read(%Security{halving_chain: nil} = security),
    do: empty(security, [], nil, :no_halving_chain)

  defp read(%Security{} = security) do
    halvings = halvings(security)
    result = Cycles.compute(series(security), halvings)

    cond do
      Enum.count(halvings, & &1.confirmed) < 2 ->
        empty(security, halvings, result, :too_few_halvings)

      Enum.all?(result.windows, &(&1.closes == 0)) ->
        empty(security, halvings, result, :no_closes)

      true ->
        security
        |> header(halvings, result)
        |> Map.merge(%{reason: nil, cycles: result.windows, intervals: result.intervals})
    end
  end

  defp empty(security, halvings, result, reason) do
    security
    |> header(halvings, result)
    |> Map.merge(%{reason: reason, cycles: [], intervals: nil})
  end

  defp header(%Security{} = security, halvings, result) do
    chain = security.halving_chain && Atom.to_string(security.halving_chain)

    %{
      security_id: security.id,
      security_name: security.name,
      currency_code: security.currency_code,
      chain: chain,
      halvings: Enum.map(halvings, &Map.put(&1, :chain, chain)),
      next_halving: result && result.next_halving,
      computation_basis: computation_basis(security, result)
    }
  end

  defp series(%Security{} = security) do
    security.id
    |> Quotes.adjusted_range(@series_floor, Clock.today())
    |> Enum.map(&%{date: &1.date, close: &1.close})
  end

  defp halvings(%Security{} = security) do
    from(e in SecurityEvent,
      where: e.security_id == ^security.id and e.kind == ^:halving,
      order_by: [asc: e.chain_height],
      select: %{
        height: e.chain_height,
        date: e.date,
        date_end: e.date_end,
        timing: e.timing,
        confirmed: e.confirmed,
        source_quality: e.source_quality
      }
    )
    |> Repo.all()
  end

  # ADR-0060 §9, the parts H4 computes: the series, the halvings, the rules
  # and the counts. The bands' parts join it with the projection (H5).
  defp computation_basis(%Security{} = security, result) do
    %{
      series: %{
        security_id: security.id,
        currency_code: security.currency_code,
        display_basis: "split_adjusted",
        description:
          "the security's own stored daily closes in its own quote currency " <>
            "#{security.currency_code}, split-adjusted at read time (ADR-0028 §2; the stored " <>
            "rows are never mutated), deliberately NOT converted: a price figure describes " <>
            "the instrument, and a conversion would fold an FX path into it (ADR-0060 §1, " <>
            "ADR-0047 §1). The whole stored history up to today; the read takes no as_of",
        closes: "positive closes only: a stored close of zero or below is not a price",
        first_close: result && result.first_close,
        last_close: result && result.last_close,
        gaps:
          "a day without a close is skipped, never filled; each window states its " <>
            "max_gap_days, the most calendar days between two of its consecutive closes"
      },
      halvings:
        "the security's halving events on its bound chain (ADR-0059): windows are formed " <>
          "from the confirmed ones in height order; the first unconfirmed one above them is " <>
          "the next halving. Halving dates are UTC dates (ADR-0059 §5)",
      window: "halving_to_halving_v1",
      window_rule:
        "a window runs from one confirmed halving's date up to the next one's, excluding " <>
          "the later date: the close dated on a halving day belongs to the window that starts " <>
          "there, because a daily close is struck after any block mined that day. The last " <>
          "window, to the newest close, is open",
      partial_days: Cycles.partial_days(),
      window_kinds:
        "a closed window is partial when it starts more than #{Cycles.partial_days()} days " <>
          "before the series' first stored close, complete otherwise; a closed window " <>
          "without a close is no_closes. A partial window has no top (before_first_close) " <>
          "and its low is marked partial: a lower close before the first stored one cannot " <>
          "be excluded",
      extremes: "max_drawdown_v1",
      extremes_rule:
        "a window's top and low are the peak and the trough of its maximum drawdown " <>
          "(close / running peak − 1, compared exactly), not its highest and lowest close: " <>
          "among equal highest closes the peak is the latest, among equal maximum drawdowns " <>
          "the earliest trough wins with its peak (ADR-0058 §2's ties). A window whose " <>
          "closes never fell below their running peak names no top and no low (no_decline). " <>
          "max_drawdown is rounded at scale 6",
      anchor_threshold: Cycles.anchor_threshold(),
      anchor_rule:
        "the open window's top and low are not final. Its top is an anchor once a close " <>
          "after it has been at least the anchor_threshold below it (the low at most " <>
          "0.80 × the top, exactly); a later recovery does not undo it, a deeper fall from a " <>
          "higher close replaces it. Until then the relations ending on a top answer " <>
          "no_top_yet. Its low anchors only when final, when the window closes at the next " <>
          "confirmed halving; until then it is low_so_far",
      counts: result && result.counts,
      intervals:
        "per relation and window: the calendar days between its two ends and, where the " <>
          "relation has one, the change (low / top − 1) or the factor (later close / earlier " <>
          "close), at scale 6. An observation exists when both its ends do; an end is a " <>
          "final top or low, or the open window's anchored top. provisional marks an " <>
          "observation with an end that is not final, partial one with a partial end. Each " <>
          "relation states n, its minimum and its maximum; nothing is averaged and nothing " <>
          "is fitted",
      ladder:
        "scope ladder levels (a) and (b): a derived figure per security and a comparison " <>
          "of the current cycle with the past ones (ADR-0060 §3). Computed at every read, " <>
          "never stored (ADR-0060 §10)"
    }
  end
end
