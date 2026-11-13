defmodule Portfolixir.Catalog.SecurityCycles do
  @moduledoc """
  The halving cycles read of one security (FR-58,
  [ADR-0060](../../docs/decisions/0060-halving-cycles-tops-and-lows-by-drawdown-projected-as-a-band.md)
  §1 to §10, §12): its past — the windows between its confirmed halvings,
  each window's top and low, and the six intervals with n, minimum and
  maximum — and its projection, the next low's and the next top's analog
  band with their parts, `agree`, states and cones, `not_a_forecast: true`.

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
  `as_of` (ADR-0060 §8), and refuses it by name, so nobody can compute a past
  cycle's band from that cycle's data.

  ## Computed at every read

  Nothing about a cycle is stored (ADR-0060 §10, ADR-0004): the same closes
  and halvings give the same answer, and a corrected close is followed by the
  next read. The read is registered with ADR-0039 as `security_cycles` at
  lifetime **`:none`** under the security's own basis, as `security_metrics`
  is: a plain call, and moving it off `:none` is a measured decision.
  """

  import Ecto.Query

  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Chains
  alias Portfolixir.Clock
  alias Portfolixir.Derived
  alias Portfolixir.Engines.Cycles
  alias Portfolixir.Knowledge.SecurityEvent
  alias Portfolixir.Repo

  # Older than any stored quote: the read takes the whole history.
  @series_floor ~D[1900-01-01]

  # The stored event's basis, carried by `next_halving` alone.
  @window_basis [:note, :checked_at, :source_url]

  @as_of_refusal "is unknown: the cycles read takes no as_of. It reads today's stored " <>
                   "closes only, because what a past cycle's band would have said, computed " <>
                   "from that cycle's data, is a replay of the band rule: level (d) of the " <>
                   "scope ladder (ADR-0060 §8)"

  @include_refusal "is invalid: include takes aligned only, the windows' closes indexed to " <>
                     "their halving day's close (ADR-0060 §11)"

  @doc """
  `{:ok, payload}` for one security, `{:error, :not_found}`, or
  `{:error, {:invalid_params, errors}}`.

  Where the view does not exist (ADR-0060 §1) the payload answers
  `cycles: []`, `intervals: nil` and a `reason`: `:no_halving_chain`
  (the security is bound to no chain), `:too_few_halvings` (fewer than two
  confirmed halvings), `:no_closes` (no close inside any window).

  **The read takes one parameter, `include`** (ADR-0060 §8, §11, §13
  items 5 and 12): `include` `aligned` (`"aligned"` or `:aligned`) adds
  `aligned`, each window's closes indexed to its halving day's close
  (`Portfolixir.Engines.Cycles.aligned/2`), off by default so the payload
  stays small. No constant can be tuned by a caller, and above all there is
  no `as_of`, because a past cycle's band computed from that cycle's data is
  a replay of the band rule, level (d). Any other parameter, and `include`
  with any other value — a query-parameter map or a keyword list — is
  refused before the lookup with `{:error, {:invalid_params, errors}}`,
  `errors` naming each parameter (`%{"as_of" => [message]}`), the shape the
  API answers with 422.

  `chain_source` is the bound chain's health (`Portfolixir.Chains.source_health/2`,
  ADR-0059 §8), `nil` for an unbound security.
  """
  @spec for_security(integer() | String.t(), map() | keyword()) ::
          {:ok, map()} | {:error, :not_found} | {:error, {:invalid_params, map()}}
  def for_security(security_id, params \\ %{}) do
    case options(params) do
      {aligned?, errors} when map_size(errors) == 0 -> read_id(security_id, aligned?)
      {_aligned?, errors} -> {:error, {:invalid_params, errors}}
    end
  end

  @doc """
  The cycles read of every security that has the view (ADR-0060 §1), in
  the order of their names: the dashboard's cards „‹Name›-Zyklus“ (§11,
  Sprint 29 H8). A security bound to no chain is not read; one whose read
  names a reason (too few halvings, no closes) is left out.
  """
  @spec views() :: [map()]
  def views do
    from(s in Security,
      where: not is_nil(s.halving_chain),
      order_by: [asc: s.name, asc: s.id],
      select: s.id
    )
    |> Repo.all()
    |> Enum.flat_map(fn id ->
      case for_security(id) do
        {:ok, %{reason: nil} = payload} -> [payload]
        _no_view -> []
      end
    end)
  end

  # Keys come from the caller's map or keyword list; an atom key is the
  # caller's own code, converted to its name, never the other way round.
  defp options(params) when is_map(params) or is_list(params) do
    Enum.reduce(params, {false, %{}}, fn {key, value}, {aligned?, errors} ->
      case {to_string(key), value} do
        {"include", include} when include in ["aligned", :aligned] -> {true, errors}
        {"include", _other} -> {aligned?, Map.put(errors, "include", [@include_refusal])}
        {name, _value} -> {aligned?, Map.put(errors, name, [refusal(name)])}
      end
    end)
  end

  defp refusal("as_of"), do: @as_of_refusal
  defp refusal(_name), do: "is unknown: the cycles read takes only include=aligned"

  defp read_id(security_id, aligned?) when is_binary(security_id) do
    case Integer.parse(security_id) do
      {id, ""} -> read_id(id, aligned?)
      _other -> {:error, :not_found}
    end
  end

  defp read_id(security_id, aligned?) when is_integer(security_id) do
    case Repo.get(Security, security_id) do
      nil -> {:error, :not_found}
      %Security{} = security -> {:ok, fetch(security, aligned?)}
    end
  end

  # Served through the derived-value axis (ADR-0039) as `:security_cycles`,
  # at the registry's `:none` lifetime (ADR-0060 §10): a plain call, computed
  # at every read, never stored. Keyed under the security's own basis and
  # today's date (the series runs to today), as `security_metrics` is; the
  # aligned form under its own key.
  defp fetch(%Security{} = security, aligned?) do
    {:fresh, payload} =
      Derived.fetch(
        :security_cycles,
        Derived.security_basis(security.id),
        "#{security.id}:#{Date.to_iso8601(Clock.today())}#{if aligned?, do: ":aligned"}",
        fn -> security |> read() |> with_aligned(aligned?) end
      )

    payload
  end

  defp read(%Security{halving_chain: nil} = security),
    do: empty(security, [], nil, :no_halving_chain)

  defp read(%Security{} = security) do
    halvings = halvings(security)
    series = series(security)
    result = Cycles.compute(series, halvings)

    cond do
      Enum.count(halvings, & &1.confirmed) < 2 ->
        empty(security, halvings, result, :too_few_halvings)

      Enum.all?(result.windows, &(&1.closes == 0)) ->
        empty(security, halvings, result, :no_closes)

      true ->
        security
        |> header(halvings, result)
        |> Map.merge(%{
          reason: nil,
          cycles: result.windows,
          intervals: result.intervals,
          projection: result.projection
        })
        |> Map.put(:series, series)
    end
  end

  # ADR-0060 §11: the windows' closes indexed to their halving day's close,
  # only on request. The series read once rides along to here and no further.
  defp with_aligned(payload, false), do: Map.delete(payload, :series)

  defp with_aligned(payload, true) do
    aligned =
      case Map.get(payload, :series) do
        nil -> []
        series -> Cycles.aligned(series, payload.cycles)
      end

    payload
    |> Map.delete(:series)
    |> Map.put(:aligned, aligned)
    |> put_in([:computation_basis, :aligned], aligned_basis())
  end

  defp aligned_basis do
    "include=aligned: per window, in the cycles' order, its closes indexed to its halving " <>
      "day's close, the last close on or before the halving date, at most " <>
      "#{Cycles.halving_close_days()} days old (base); each point is a close inside the " <>
      "window as the calendar days since the halving (its date is the window's start + " <>
      "the days) and close / base at scale 6. A window without such a close is left out: base null, no points, reason " <>
      "no_halving_close. The same split-adjusted closes in the security's own currency as " <>
      "the windows; nothing is filled"
  end

  # No view, no band: the projection header still says what it would be.
  defp empty(security, halvings, result, reason) do
    security
    |> header(halvings, result)
    |> Map.merge(%{
      reason: reason,
      cycles: [],
      intervals: nil,
      projection: %{
        kind: :analog_band,
        not_a_forecast: true,
        next_low: nil,
        next_top: nil,
        cones: []
      }
    })
  end

  defp header(%Security{} = security, halvings, result) do
    chain = security.halving_chain && Atom.to_string(security.halving_chain)

    %{
      security_id: security.id,
      security_name: security.name,
      currency_code: security.currency_code,
      chain: chain,
      chain_source: security.halving_chain && Chains.source_health(security.halving_chain),
      halvings: Enum.map(halvings, &(&1 |> Map.drop(@window_basis) |> Map.put(:chain, chain))),
      next_halving: next_halving(security, halvings, result),
      computation_basis: computation_basis(security, result)
    }
  end

  # ADR-0059 §6: the next halving's window with its basis in full — the
  # stored event's note, day of reading and source link, and the chain
  # source's current inputs (`Chains.next_halving_inputs/1`, nil for a chain
  # without a source). The closing act's analytics lens on Lane H.
  defp next_halving(_security, _halvings, nil), do: nil
  defp next_halving(_security, _halvings, %{next_halving: nil}), do: nil

  defp next_halving(%Security{} = security, halvings, %{next_halving: next}) do
    event = Enum.find(halvings, &(&1.height == next.height and not &1.confirmed))

    next
    |> Map.merge(Map.take(event || %{}, @window_basis))
    |> Map.put_new(:note, nil)
    |> Map.put_new(:checked_at, nil)
    |> Map.put_new(:source_url, nil)
    |> Map.put(:inputs, Chains.next_halving_inputs(security.halving_chain))
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
        source_quality: e.source_quality,
        note: e.note,
        checked_at: e.checked_at,
        source_url: e.source_url
      }
    )
    |> Repo.all()
  end

  # ADR-0060 §9: the series, the halvings, the rules, the counts (H4) and the
  # projection's rules (H5).
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
      next_halving:
        "the next halving's window as stored (ADR-0059 §6): date to date_end, with the " <>
          "event's own note (its basis in one line: the tip, its time, the block 2,016 " <>
          "below, the mean block time, both ends), checked_at (the day it was written) " <>
          "and source_url; and inputs, the chain source's current inputs (tip_height, " <>
          "tip_at, tip_2016_at, period_blocks, mean_block_seconds), null for a chain " <>
          "without a source or before its first run. The window is written at most once " <>
          "a day, so inputs can be newer than the note",
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
      projection: projection_basis(),
      ladder:
        "scope ladder levels (a) and (b) for the windows, tops, lows and intervals: a " <>
          "derived figure per security and a comparison of the current cycle with the past " <>
          "ones (ADR-0060 §3); the projection is the ladder's analog band entry, a range " <>
          "with n and both ends, never a single date or price, never fitted (ADR-0060 §8). " <>
          "Computed at every read, never stored (ADR-0060 §10)"
    }
  end

  # ADR-0060 §9, the projection's part of the basis (Sprint 29 H5). Each
  # part carries its own time_rule, price_rule with its reason, the factors
  # used, n_time, n_price and price_from where borrowed; this says how they
  # were read.
  defp projection_basis do
    %{
      kind: "analog_band",
      not_a_forecast: true,
      events:
        "next_low is the open window's low; next_top is the top of the first window " <>
          "without an anchored top (the open window's, or once its top is anchored the " <>
          "next window's). next_low's parts: top_to_low from the open window's anchored " <>
          "top (no_top_yet before it anchors), low_to_low from the last final low. " <>
          "next_top's parts: halving_to_top from that window's halving (the next halving's " <>
          "window, ADR-0059 §6, once the open top is anchored), top_to_top from the last " <>
          "anchored top, low_to_top from the last final low with no top after it " <>
          "(low_not_final while the open window's top is anchored and its low is not final)",
      time_rule: "min_max",
      time_rule_text:
        "a part's window runs from its anchor's date + the minimum to + the maximum of " <>
          "its relation's past days; halving_to_top's from the halving window's first day + " <>
          "the minimum to its last day + the maximum. The days show no trend from cycle to " <>
          "cycle, so the past range is the range",
      price_rule: "log_step_v1",
      price_rule_text:
        "a part's price range is its anchor's close × the factors from the last factor f₂ " <>
          "to f₂^(ln f₂ / ln f₁), in either order, with f₁ and f₂ the relation's last two " <>
          "factors, oldest first: the shrinking stops, or it goes on as last time. " <>
          "Only these two factors enter. top_to_low uses the factor 1 + change. " <>
          "halving_to_top has no price relation of its own and borrows top_to_top's " <>
          "(price_from), absent whenever that part is. Factors and prices at scale 6",
      price_fallback:
        "where no step is defined — ln f₁ or ln f₂ is 0 (a factor of exactly 1), the two " <>
          "differ in sign (the factor crossed 1), or the step leaves the double range or " <>
          "rounds to 0 at scale 6 — " <>
          "the price side is the minimum to the maximum of the relation's stored factors, " <>
          "price_rule min_max with price_reason no_log_step. A step that grows the factor " <>
          "is taken as it comes",
      float_island:
        "the log step is AR-3's fourth float operation, :math.log/1, with :math.pow/2: " <>
          "Decimals in, Decimal.from_float/1 then Decimal.round/2 at scale 6 out; nothing " <>
          "float is kept",
      minimum_data:
        "a part needs at least two observations for its time side and two factors for " <>
          "its price side, or it is absent with too_few_observations and its n_time and " <>
          "n_price: with one observation a band is a point. A part whose window is one day " <>
          "or whose price range is one price is absent with zero_width, for the same reason. " <>
          "Provisional and partial observations count, and mark the part",
      band:
        "one band per event: the hull of its present parts, in time from the earliest " <>
          "start to the latest end, in price from the lowest lower end to the highest upper " <>
          "end. Nothing is averaged and nothing is intersected: the parts are read from the " <>
          "same lows and tops, two views of one sample. No present part: no band, no_parts",
      agree:
        "the price range where every part with a price side of its own overlaps, from the " <>
          "highest lower end to the lowest upper end; null with one_price_relation when " <>
          "fewer than two parts have their own price side, with parts_disjoint when the " <>
          "range is empty or a single price",
      state:
        "read from the stored closes against the last stored close, so the same closes " <>
          "give the same state: open before the window starts; reached once a close inside " <>
          "the window lies within the price range, inclusive; running while the window has " <>
          "started without one; missed once it has ended without one; window_ended once " <>
          "the last stored close is on or after the window's last day. Every close that " <>
          "went into a band (its anchors' and observations', up to inputs_until) must " <>
          "predate its window, or the state is null with input_after_window. A state is " <>
          "not a score: nothing counts or aggregates states",
      cones:
        "each line continues from its last anchor into its own relation's part, never past " <>
          "the anchor as a line: top_low into top_to_low after a top and into low_to_top " <>
          "after a final low, top_top into top_to_top, low_low into low_to_low; " <>
          "halving_to_top has none. A cone into an absent part has no apex and carries the " <>
          "part's reason",
      not_computed:
        "not_a_forecast: no point (no single date or price), no fit, no average, and no " <>
          "past cycle's band: the read takes no as_of, because scoring the band rule on " <>
          "past cycles is level (d) (ADR-0060 §8). A caller who wants to stand behind one " <>
          "figure records an ADR-0055 prediction"
    }
  end
end
