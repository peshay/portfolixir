defmodule Portfolixir.Imports.SecurityResolver do
  @moduledoc """
  The ADR-0029 §2 stable-identity ladder for import securities.

  A security reference from a Portfolio Performance export resolves against
  existing securities by descending a fixed ladder — 1 ISIN (current ISINs
  first, then the §3 former-ISIN aliases), 2 WKN, 3 `(ticker, currency)`,
  4 `(name, currency)`. Determinism rules, all binding:

    * a tier applies only when its field is present on **both** sides, in the
      catalog normal form (trimmed, upcased ISIN/WKN/ticker; trimmed name);
    * a tier with zero candidates falls through to the next tier;
    * a tier matching **ambiguously** (>= 2 candidates) neither picks nor
      falls through — the entry becomes a surfaced decision;
    * **stronger-identifier veto**: a weaker-tier unique match whose candidate
      differs on a *strictly stronger* identifier present on both sides (entry
      ISIN vs. candidate ISIN, entry WKN vs. candidate WKN, and — at the name
      tier — entry ticker vs. candidate ticker, since ticker+currency is
      stronger than name+currency), and any cross-tier disagreement (WKN
      selects A, ticker+currency selects B), is surfaced as a conflict, never
      accepted silently;
    * an entry without a currency does not enter tiers 3–4;
    * matching never mutates matched master data — the resolver is read-only.

  Lookup structures are **multi-valued (grouped)** wherever the schema does
  not guarantee uniqueness, so ambiguity is expressible instead of silently
  last-won; only the ISIN maps stay single-valued (both `securities.isin` and
  `security_identifier_aliases.former_isin` carry unique indexes, and the §3
  bidirectional guard keeps the two disjoint).

  On top of the ladder this module derives the preview machinery of §2:
  `resolution_plan/2` (one classified row per unique reference, with a stable
  form-safe key), `config_at_risk/2` (a to-be-created reference near-matching
  an existing security that carries stored category assignments or position
  targets, ADR-0030), and `unmatched_config_securities/2` (the pre-apply
  inverse check: config-bearing, transacted securities matched by zero
  entries).
  """

  alias Portfolixir.Catalog.IdentifierAlias
  alias Portfolixir.Catalog.IdentifierAliases
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Classifications
  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.Targets
  alias Portfolixir.Repo

  import Ecto.Query

  @type tier :: :isin | :former_isin | :wkn | :ticker | :name

  @type ref :: %{
          isin: String.t() | nil,
          wkn: String.t() | nil,
          ticker: String.t() | nil,
          name: String.t() | nil,
          currency: String.t() | nil
        }

  @type conflict :: %{
          type: :ambiguous | :identifier_veto | :cross_tier,
          tier: tier(),
          candidates: [Security.t()]
        }

  @type outcome :: {:match, Security.t(), tier()} | {:conflict, conflict()} | :create

  defmodule Index do
    @moduledoc false
    defstruct securities_by_id: %{},
              by_isin: %{},
              by_former_isin: %{},
              by_wkn: %{},
              by_ticker_ccy: %{},
              by_name_ccy: %{},
              by_name: %{},
              by_ticker: %{},
              assignment_ids: MapSet.new(),
              position_target_ids: MapSet.new(),
              transacted_ids: MapSet.new()

    @type t :: %__MODULE__{}
  end

  @doc """
  Loads a read-only snapshot of every existing security, the former-ISIN alias
  table, and the config-bearing/transacted security-id sets the §2 preview
  machinery needs. Grouped maps are multi-valued.
  """
  @spec load_index() :: Index.t()
  def load_index do
    securities = Repo.all(from(s in Security, order_by: s.id))
    by_id = Map.new(securities, &{&1.id, &1})

    by_former_isin =
      IdentifierAliases.by_former_isin()
      |> Map.new(fn {former, security_id} -> {former, Map.fetch!(by_id, security_id)} end)

    %Index{
      securities_by_id: by_id,
      by_isin: Map.new(for(s <- securities, s.isin, do: {s.isin, s})),
      by_former_isin: by_former_isin,
      by_wkn: group_by_field(securities, & &1.wkn),
      by_ticker_ccy: group_by_field(securities, &ticker_ccy_key/1),
      by_name_ccy: group_by_field(securities, &name_ccy_key/1),
      by_name: group_by_field(securities, &normalize_name(&1.name)),
      by_ticker: group_by_field(securities, & &1.ticker_symbol),
      assignment_ids: Classifications.security_ids_with_assignments(),
      position_target_ids: Targets.security_ids_with_position_targets(),
      transacted_ids: Ledger.security_ids_with_transactions()
    }
  end

  defp group_by_field(securities, fun) do
    securities
    |> Enum.map(&{fun.(&1), &1})
    |> Enum.reject(fn {key, _} -> is_nil(key) end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp ticker_ccy_key(%Security{ticker_symbol: nil}), do: nil
  defp ticker_ccy_key(%Security{ticker_symbol: ticker, currency_code: ccy}), do: {ticker, ccy}

  defp name_ccy_key(%Security{name: name, currency_code: ccy}) do
    case normalize_name(name) do
      nil -> nil
      normalized -> {normalized, ccy}
    end
  end

  @doc """
  Catalog normal form for an import security reference: trimmed/upcased
  ISIN/WKN/ticker/currency, trimmed name, blank values to `nil`. Accepts the
  parser's `Entry.security_ref` map (string or atom access tolerated via
  `Map.get/2` on atom keys only — parser refs carry atom keys).
  """
  @spec normalize_ref(map()) :: ref()
  def normalize_ref(ref) when is_map(ref) do
    %{
      isin: IdentifierAlias.normalize_isin(Map.get(ref, :isin)),
      wkn: normalize_code(Map.get(ref, :wkn)),
      ticker: normalize_code(Map.get(ref, :ticker)),
      name: normalize_name(Map.get(ref, :name)),
      currency: normalize_code(Map.get(ref, :currency))
    }
  end

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

  @doc """
  A stable, form-field-safe key for a normalized reference: the SHA-256 (hex,
  truncated to 128 bits) of the canonical identity string. The preview's
  override form, the applier's `security_mappings`, and the preview→apply
  revalidation all address a reference by this key.
  """
  @spec key(ref()) :: String.t()
  def key(%{} = ref) do
    [ref.isin, ref.wkn, ref.ticker, ref.name, ref.currency]
    |> Enum.map(&(&1 || ""))
    |> Enum.join("|")
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 32)
  end

  @doc "True when the reference carries no usable identity at all."
  @spec blank_ref?(ref()) :: boolean()
  def blank_ref?(%{} = ref) do
    is_nil(ref.isin) and is_nil(ref.wkn) and is_nil(ref.ticker) and is_nil(ref.name)
  end

  @doc """
  Descends the ladder for one normalized reference against the index. Returns
  `{:match, security, tier}`, `{:conflict, conflict}` (a surfaced decision),
  or `:create`.
  """
  @spec resolve(ref(), Index.t()) :: outcome()
  def resolve(%{} = ref, %Index{} = index) do
    ref
    |> tier_outcomes(index)
    |> walk_tiers(ref)
  end

  # Per-tier outcome: :absent (field missing on the entry side — candidates
  # carry the field by index construction), :none (zero candidates, falls
  # through), {:unique, security} or {:unique, security, label},
  # {:ambiguous, securities}.
  defp tier_outcomes(ref, index) do
    [
      {:isin, isin_tier(ref, index)},
      {:wkn, grouped_tier(index.by_wkn, ref.wkn)},
      {:ticker, grouped_tier(index.by_ticker_ccy, currency_key(ref.ticker, ref.currency))},
      {:name, grouped_tier(index.by_name_ccy, currency_key(ref.name, ref.currency))}
    ]
  end

  defp currency_key(_value, nil), do: nil
  defp currency_key(nil, _currency), do: nil
  defp currency_key(value, currency), do: {value, currency}

  # Tier 1: current ISINs first, then the §3 alias table. Both maps are
  # single-valued under unique indexes and disjoint under the bidirectional
  # guard, so this tier cannot be ambiguous.
  defp isin_tier(%{isin: nil}, _index), do: :absent

  defp isin_tier(%{isin: isin}, index) do
    case Map.fetch(index.by_isin, isin) do
      {:ok, security} ->
        {:unique, security, :isin}

      :error ->
        case Map.fetch(index.by_former_isin, isin) do
          {:ok, security} -> {:unique, security, :former_isin}
          :error -> :none
        end
    end
  end

  defp grouped_tier(_map, nil), do: :absent

  defp grouped_tier(map, key) do
    case Map.get(map, key, []) do
      [] -> :none
      [security] -> {:unique, security}
      securities -> {:ambiguous, securities}
    end
  end

  defp walk_tiers([], _ref), do: :create

  defp walk_tiers([{_tier, outcome} | rest], ref) when outcome in [:absent, :none] do
    walk_tiers(rest, ref)
  end

  defp walk_tiers([{tier, {:ambiguous, candidates}} | _rest], _ref) do
    {:conflict, %{type: :ambiguous, tier: tier, candidates: candidates}}
  end

  defp walk_tiers([{tier, unique} | rest], ref) do
    {security, label} =
      case unique do
        {:unique, security, label} -> {security, label}
        {:unique, security} -> {security, tier}
      end

    with :ok <- stronger_identifier_veto(tier, ref, security),
         :ok <- cross_tier_agreement(security, rest) do
      {:match, security, label}
    else
      {:conflict, _} = conflict -> conflict
    end
  end

  # ADR-0029 §2 stronger-identifier veto: only identifiers STRICTLY stronger
  # than the matched tier can contradict it. An alias-tier hit is part of tier
  # 1 and deliberately not vetoed by the candidate's different current ISIN —
  # that difference is the recorded ISIN change itself.
  defp stronger_identifier_veto(:isin, _ref, _security), do: :ok

  defp stronger_identifier_veto(tier, ref, security) do
    stronger =
      case tier do
        :wkn -> [:isin]
        :ticker -> [:isin, :wkn]
        :name -> [:isin, :wkn, :ticker]
      end

    case Enum.find(stronger, &identifier_mismatch?(&1, ref, security)) do
      nil -> :ok
      _field -> {:conflict, %{type: :identifier_veto, tier: tier, candidates: [security]}}
    end
  end

  defp identifier_mismatch?(:isin, ref, security) do
    is_binary(ref.isin) and is_binary(security.isin) and ref.isin != security.isin
  end

  defp identifier_mismatch?(:wkn, ref, security) do
    is_binary(ref.wkn) and is_binary(security.wkn) and ref.wkn != security.wkn
  end

  defp identifier_mismatch?(:ticker, ref, security) do
    is_binary(ref.ticker) and is_binary(security.ticker_symbol) and
      ref.ticker != security.ticker_symbol
  end

  # Cross-tier disagreement: a weaker applicable tier uniquely selecting a
  # DIFFERENT security than the accepted match is surfaced, never resolved by
  # rank alone.
  defp cross_tier_agreement(security, weaker_tiers) do
    disagreeing =
      for {tier, {:unique, other}} <- weaker_tiers, other.id != security.id, do: {tier, other}

    case disagreeing do
      [] ->
        :ok

      [{tier, other} | _] ->
        {:conflict, %{type: :cross_tier, tier: tier, candidates: [security, other]}}
    end
  end

  @doc """
  The §2 config-at-risk check (FR-7) for a reference that would be created:
  existing securities that near-match it (same normalized name in any
  currency, or same ticker in any currency) **and** carry stored category
  assignments or position targets (ADR-0030). Returns
  `[%{security: security, assignments?: boolean, position_targets?: boolean}]`.
  """
  @spec config_at_risk(ref(), Index.t()) :: [map()]
  def config_at_risk(%{} = ref, %Index{} = index) do
    (Map.get(index.by_name, ref.name, []) ++ Map.get(index.by_ticker, ref.ticker, []))
    |> Enum.uniq_by(& &1.id)
    |> Enum.filter(&config_bearing?(&1.id, index))
    |> Enum.map(fn security ->
      %{
        security: security,
        assignments?: MapSet.member?(index.assignment_ids, security.id),
        position_targets?: MapSet.member?(index.position_target_ids, security.id)
      }
    end)
  end

  defp config_bearing?(id, index) do
    MapSet.member?(index.assignment_ids, id) or MapSet.member?(index.position_target_ids, id)
  end

  @doc """
  Classifies every unique security reference of a preview: one row per
  normalized reference (rows repeating a reference collapse onto it), with

    * `key` — the stable `key/1` string,
    * `ref` — the normalized reference,
    * `rows` — the source rows carrying it,
    * `status` — `:matched` | `:create` | `:needs_decision` | `:config_at_risk`,
    * `matched` — `%{security_id:, tier:}` for `:matched`,
    * `name_differs` — the file's name when it differs from the stored one
      (matched rows only; matching never renames stored master data),
    * `conflict` / `candidates` — the surfaced decision for `:needs_decision`,
    * `at_risk` — the `config_at_risk/2` list for `:config_at_risk`.
  """
  @spec resolution_plan(Preview.t(), Index.t()) :: [map()]
  def resolution_plan(%Preview{entries: entries}, %Index{} = index) do
    entries
    |> Entry.flatten()
    |> Enum.filter(& &1.security)
    |> Enum.map(fn entry -> {effective_ref(entry), entry.source_row} end)
    |> Enum.reject(fn {ref, _row} -> blank_ref?(ref) end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {ref, rows} -> classify(ref, rows, index) end)
    |> Enum.sort_by(&{status_rank(&1.status), &1.label})
  end

  @doc """
  The effective normalized reference of an entry: the parsed security ref with
  the booking currency as currency fallback (a CSV export carries no security
  currency, but its bookings do). No further guessing — a reference that still
  has no currency skips tiers 3–4.
  """
  @spec effective_ref(Entry.t()) :: ref()
  def effective_ref(%Entry{security: security} = entry) do
    normalized = normalize_ref(security || %{})
    %{normalized | currency: normalized.currency || normalize_code(entry.currency_code)}
  end

  defp classify(ref, rows, index) do
    base = %{
      key: key(ref),
      ref: ref,
      label: ref.name || ref.isin || ref.wkn || ref.ticker,
      rows: Enum.sort(rows),
      matched: nil,
      name_differs: nil,
      conflict: nil,
      candidates: [],
      at_risk: []
    }

    case resolve(ref, index) do
      {:match, security, tier} ->
        base
        |> Map.put(:status, :matched)
        |> Map.put(:matched, %{security_id: security.id, tier: tier})
        |> Map.put(:name_differs, differing_name(ref, security))
        |> Map.put(:security, security)

      {:conflict, conflict} ->
        base
        |> Map.put(:status, :needs_decision)
        |> Map.put(:conflict, conflict)
        |> Map.put(:candidates, conflict.candidates)

      :create ->
        case config_at_risk(ref, index) do
          [] -> Map.put(base, :status, :create)
          at_risk -> base |> Map.put(:status, :config_at_risk) |> Map.put(:at_risk, at_risk)
        end
    end
  end

  # Matching never mutates stored master data (ADR-0029 §2), so a renamed
  # export would otherwise match silently and leave no trace that the file now
  # calls the security something else. The row carries the file's name; the
  # stored one is untouched (#609).
  defp differing_name(%{name: name}, security) when is_binary(name) do
    if comparable_name(name) == comparable_name(security.name), do: nil, else: name
  end

  defp differing_name(_ref, _security), do: nil

  defp comparable_name(nil), do: nil
  defp comparable_name(name), do: name |> String.split() |> Enum.join(" ") |> String.downcase()

  # Decisions first, then warnings, creations, matches — the order the
  # preview renders attention in.
  defp status_rank(:needs_decision), do: 0
  defp status_rank(:config_at_risk), do: 1
  defp status_rank(:create), do: 2
  defp status_rank(:matched), do: 3

  # Below this many leftovers the list is readable, so it is shown even for an
  # incremental file — the noise problem #607 describes starts at dozens.
  @leftover_noise_floor 5

  @doc """
  The §2 pre-apply inverse check: every config-bearing security (stored
  assignments or position targets) that is **transacted** (surfacing is scoped
  to securities affected by imports — a watch-only row without bookings is
  excluded so it does not drown the signal) and matches zero entries of the
  import — neither as a match nor as a candidate of a surfaced decision or
  config-at-risk warning. Returns
  `[%{security:, assignments?:, position_targets?:}]`.
  """
  @spec unmatched_config_securities([map()], Index.t()) :: [map()]
  def unmatched_config_securities(resolutions, %Index{} = index) do
    case unmatched_config_scope(resolutions, index) do
      :incremental -> []
      :full_export -> leftovers(resolutions, index)
    end
  end

  @doc """
  Whether the import looks like a **full re-export** — the case the §2 inverse
  check is written for — or an **incremental** file (issue #607).

  The check lists every transacted, config-bearing security the import does not
  touch. On a full re-export that is exactly the renamed or ISIN-changed
  security. On a small incremental file it is every *other* configured security
  in the portfolio, so the one real signal drowns in dozens of irrelevant rows.

  Two conditions must BOTH hold for the check to be skipped:

    * the file references fewer than half of the transacted securities, so it
      reads as adding bookings rather than re-exporting a history; and
    * the resulting list would be long enough to actually drown the signal
      (more than #{@leftover_noise_floor} rows).

  A short leftover list is signal, not noise, and is shown whatever the file
  looks like. Coverage rather than portfolio/depot scoping because a preview's
  accounts are still unmapped PP names at this point — the security references
  are the only resolved thing available before apply. Both thresholds lean
  toward showing: a false `:full_export` costs noise, a false `:incremental`
  hides a rename.
  """
  @spec unmatched_config_scope([map()], Index.t()) :: :full_export | :incremental
  def unmatched_config_scope(resolutions, %Index{} = index) do
    transacted = index.transacted_ids
    covered = MapSet.size(MapSet.intersection(touched_ids(resolutions), transacted))
    total = MapSet.size(transacted)
    broad? = total == 0 or covered * 2 >= total

    if broad? or length(leftovers(resolutions, index)) <= @leftover_noise_floor do
      :full_export
    else
      :incremental
    end
  end

  defp leftovers(resolutions, %Index{} = index) do
    touched = touched_ids(resolutions)

    index.securities_by_id
    |> Map.values()
    |> Enum.filter(fn security ->
      config_bearing?(security.id, index) and
        MapSet.member?(index.transacted_ids, security.id) and
        not MapSet.member?(touched, security.id)
    end)
    |> Enum.sort_by(& &1.name)
    |> Enum.map(fn security ->
      %{
        security: security,
        assignments?: MapSet.member?(index.assignment_ids, security.id),
        position_targets?: MapSet.member?(index.position_target_ids, security.id)
      }
    end)
  end

  defp touched_ids(resolutions) do
    resolutions
    |> Enum.flat_map(fn resolution ->
      matched = if resolution.matched, do: [resolution.matched.security_id], else: []

      matched ++
        Enum.map(resolution.candidates, & &1.id) ++
        Enum.map(resolution.at_risk, & &1.security.id)
    end)
    |> MapSet.new()
  end
end
