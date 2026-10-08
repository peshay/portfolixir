defmodule Portfolixir.Imports do
  @moduledoc """
  Top-level public API for bulk-importing transaction exports.

  Today only Portfolio Performance CSV and JSON v1 are supported (see
  AGENTS.md goal #9). PP XML, the binary `.portfolio` workspace file
  and broker-PDF intake are explicit follow-ups.

  Workflow:

      {:ok, preview} = Imports.parse_portfolio_performance(body, filename: "Alle_Buchungen.json")

      preview.entries              # normalised Entry list
      Preview.counts_by_kind(preview)
      Preview.unique_securities(preview)
      Preview.unique_pp_account_pairs(preview)

      # Imports.apply/2 turns a preview plus mapping into committed rows via
      # Ecto.Multi, using content-hash idempotency so re-runs skip duplicates.
  """

  alias Portfolixir.Actor
  alias Portfolixir.Imports.Applier
  alias Portfolixir.Imports.Correction
  alias Portfolixir.Imports.Mapping
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Imports.SecurityResolver
  alias Portfolixir.Lifecycle.AccountNames
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.SecuritiesAccount

  @spec parse_portfolio_performance(binary(), keyword()) :: {:ok, Preview.t()} | {:error, term()}
  def parse_portfolio_performance(body, opts \\ []) when is_binary(body) do
    PortfolioPerformance.parse(body, opts)
  end

  @doc """
  Runs the ADR-0029 §2 identity ladder over a parsed preview against the
  current database: one classified resolution row per unique security
  reference (matched / create / needs-decision / config-at-risk), plus the
  pre-apply inverse check (config-bearing securities matched by zero
  entries). Read-only — the preview UI uses it to drive the security-mapping
  step before `apply/2`.
  """
  @spec resolve_securities(Preview.t()) :: %{
          resolutions: [map()],
          unmatched_config: [map()],
          unmatched_config_scope: :full_export | :incremental
        }
  def resolve_securities(%Preview{} = preview) do
    index = SecurityResolver.load_index()
    resolutions = SecurityResolver.resolution_plan(preview, index)

    %{
      resolutions: resolutions,
      unmatched_config: SecurityResolver.unmatched_config_securities(resolutions, index),
      unmatched_config_scope: SecurityResolver.unmatched_config_scope(resolutions, index)
    }
  end

  @doc """
  Whether a resolution of `resolve_securities/1` still needs the operator's
  choice, given its key's counts from `reimport_counts/2`'s `securities`: a
  surfaced decision whose rows are all already imported by their hash needs
  none, because the apply never reaches it (ADR-0050 §3, #923); a key
  collision always does. See `SecurityResolver.decision_needed?/2`.
  """
  @spec security_decision_needed?(map(), Applier.layer_counts()) :: boolean()
  defdelegate security_decision_needed?(resolution, counts),
    to: SecurityResolver,
    as: :decision_needed?

  @doc """
  Whether the apply resolves nothing for a security key, given its counts
  from `reimport_counts/2`'s `securities`: every row of it is skipped before
  the ladder runs (#923), so no security is created or matched for it. See
  `SecurityResolver.resolves_nothing?/1`.
  """
  @spec security_resolves_nothing?(Applier.layer_counts()) :: boolean()
  defdelegate security_resolves_nothing?(counts), to: SecurityResolver, as: :resolves_nothing?

  @doc """
  The already-imported counts of a parsed preview (ADR-0050 §3), before the
  apply: per layer that judges a row (`:hash`, `:retired`, `:unimportable`,
  `:economics`, `:internal_transfer`, `:new`) in `total`, and per file
  cash-account and depot name, where a row counts under every name it
  carries; per security reference (`securities`, keyed as
  `resolve_securities/1` keys its resolutions) on the hash layers alone
  (#923); and the file's names unknown to the stored history
  (`unseen_names`, ADR-0050 §2 as amended on 2026-10-07: no row under the
  name is held by a stored or a retired content hash, while another name of
  the file has one), which the preview leaves without a prefill. See
  `Portfolixir.Imports.Applier.reimport_counts/3`; `dry_run: false` counts on
  the hash layers alone, without the rolled-back run of the apply that judges
  the rest, and names the same unseen names.

  Read-only. The hash names the portfolio the import binds to: `:portfolio_id`
  when given, otherwise the internal default portfolio the Imports view binds
  to (ADR-0024), read without creating it — before the first import there is
  none, and every importable row is new.
  """
  @spec reimport_counts(Preview.t(), keyword()) :: %{
          total: Applier.layer_counts(),
          cash_accounts: %{String.t() => Applier.layer_counts()},
          depots: %{String.t() => Applier.layer_counts()},
          securities: %{String.t() => Applier.layer_counts()},
          unseen_names: Applier.unseen_names()
        }
  def reimport_counts(%Preview{} = preview, opts \\ []) when is_list(opts) do
    Applier.reimport_counts(preview, import_portfolio_id(opts),
      dry_run: Keyword.get(opts, :dry_run, true)
    )
  end

  @doc """
  How each Portfolio Performance cash-account and depot name of a parsed
  preview resolves (ADR-0050 §4), for the preview's prefill: the one function
  the applier resolves an unmapped name with
  (`Portfolixir.Lifecycle.AccountNames.resolve/2`) — the exact live name of
  the kind in the portfolio, then a former name.

    * `{:ok, id, :live | :former}` — prefill that account;
    * `:none` — prefill "+ Create new";
    * `{:ambiguous, tier, ids}` — prefill nothing: the apply refuses the name
      unmapped.

  Read-only. The portfolio is `:portfolio_id` when given, otherwise the
  internal default portfolio the Imports view binds to (ADR-0024), read
  without creating it.
  """
  @spec resolve_accounts(Preview.t(), keyword()) :: %{
          cash_accounts: %{String.t() => AccountNames.resolution()},
          depots: %{String.t() => AccountNames.resolution()}
        }
  def resolve_accounts(%Preview{} = preview, opts \\ []) when is_list(opts) do
    portfolio_id = import_portfolio_id(opts)
    cash = AccountNames.index(CashAccount, portfolio_id)
    depots = AccountNames.index(SecuritiesAccount, portfolio_id)

    %{
      cash_accounts:
        Map.new(Mapping.unique_cash_pp_names(preview), &{&1, AccountNames.resolve(cash, &1)}),
      depots:
        Map.new(Mapping.unique_depot_pp_names(preview), &{&1, AccountNames.resolve(depots, &1)})
    }
  end

  @doc """
  What remembering the Portfolio Performance name `name` on the account
  `account_id` would do, for the preview to say before the import is applied
  (ADR-0050 §4): `:same_name`, `:already`, `:append`, `{:move, from_id}` (a
  former name of that account moves), `{:not_offered, live_on_id}` (the live
  name of that account: the choice holds for this import only; merge or
  rename that account to change it), or `:not_found`. Read-only.
  """
  @spec remember_outcome(:cash_account | :securities_account, String.t(), integer()) ::
          AccountNames.remember_outcome() | :not_found
  def remember_outcome(:cash_account, name, account_id),
    do: AccountNames.remember_outcome(CashAccount, account_id, name)

  def remember_outcome(:securities_account, name, account_id),
    do: AccountNames.remember_outcome(SecuritiesAccount, account_id, name)

  defp import_portfolio_id(opts) do
    Keyword.get_lazy(opts, :portfolio_id, fn ->
      case Portfolios.first_portfolio() do
        nil -> nil
        portfolio -> portfolio.id
      end
    end)
  end

  @spec apply(Preview.t(), Applier.apply_params()) :: {:ok, Applier.Result.t()} | {:error, term()}
  defdelegate apply(preview, params), to: Applier

  @doc """
  The bookings already imported whose stored cash differs from what the
  rows of a parsed preview book today (ADR-0053 §6, A6), for the preview's
  correction section: each found by the content hash its row still carries,
  in file order. See `Portfolixir.Imports.Correction.detect/3`.

  Read-only. The portfolio is `:portfolio_id` when given, otherwise the
  internal default portfolio the Imports view binds to (ADR-0024), read
  without creating it — before the first import there is none, and nothing
  is listed.
  """
  @spec cash_corrections(Preview.t(), keyword()) :: [Correction.Item.t()]
  def cash_corrections(%Preview{} = preview, opts \\ []) when is_list(opts),
    do: Correction.detect(preview, import_portfolio_id(opts))

  @doc """
  Corrects the bookings `cash_corrections/2` lists for `preview`, on
  behalf of `actor` (ADR-0053 §6, A6): the correction section's own confirm,
  separate from `apply/2`, whose hash hits still change nothing (ADR-0050
  §3). Each booking's cash — and a JSON trade's price, and a cross-currency
  trade's settlement legs — is rewritten through the ledger's own update,
  journaled with its before-image, under the apply's lock. Answers the
  corrected items; a second run finds nothing to correct. See
  `Portfolixir.Imports.Correction.apply/3`.

  An operator action like the import itself: no API route and no MCP tool
  (ADR-0029). The portfolio is `:portfolio_id` when given, otherwise the
  internal default portfolio (ADR-0024); without one there is nothing to
  correct.
  """
  @spec correct_cash(Actor.t(), Preview.t(), keyword()) ::
          {:ok, [Correction.Item.t()]} | {:error, %{row: term(), reason: term()}}
  def correct_cash(%Actor{} = actor, %Preview{} = preview, opts \\ []) when is_list(opts) do
    case import_portfolio_id(opts) do
      nil -> {:ok, []}
      portfolio_id -> Correction.apply(actor, preview, portfolio_id)
    end
  end

  @doc """
  The actor a correction confirmed on the Imports page is journaled under:
  the operator (`:owner_ui`), labelled as an import correction, so the
  journal tells it from an edit made by hand (ADR-0053 §6).
  """
  @spec correction_actor() :: Actor.t()
  def correction_actor, do: Actor.new(:owner_ui, "import correction")
end
