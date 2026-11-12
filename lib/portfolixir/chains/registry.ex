defmodule Portfolixir.Chains.Registry do
  @moduledoc """
  The block chains the app knows (ADR-0059 §2): a closed set of **protocol
  constants** in code, never detected and never stored as rows.

  | Chain | `halving_interval` (blocks) | `target_spacing` (seconds) | Source |
  |---|---|---|---|
  | `bitcoin` | 210,000 | 600 | ADR-0059 §3 |
  | `bitcoin_cash` | 210,000 | 600 | none |
  | `litecoin` | 840,000 | 150 | none |

  The constants are the subsidy halving interval and the target block
  spacing as each chain's reference client states them in its consensus
  parameters (Bitcoin Core's `nSubsidyHalvingInterval` and its ten-minute
  spacing; Bitcoin Cash inherited both at the fork of 2017; Litecoin's
  840,000 blocks at two and a half minutes). Halving *k* is the block at
  height *k* × `halving_interval`, *k* ≥ 1.

  *Why constants in code and not rows:* they are the same on every
  instance, they are facts of the protocol rather than settings, and a row
  would let one mistyped digit produce a wrong cycle that nothing could
  notice. A chain is added by an amendment of ADR-0059 that names its
  constants and their source. **Not registered:** Zcash, whose interval
  changed at a network upgrade, and every coin without halvings.

  Only Bitcoin has a source (ADR-0059 §3); for the other two the constants
  are registered so that a security can be bound and a hand-written halving
  is checked against its interval (ADR-0048's amendment of 2026-11-12,
  item 2).

  A name from outside is mapped through the known list (`fetch/1`); no atom
  is ever made from input (`AGENTS.md`).
  """

  @typedoc "A registered chain."
  @type chain :: :bitcoin | :bitcoin_cash | :litecoin

  # The public genesis block hash of Bitcoin (height 0), which ADR-0059 §7's
  # daily check compares a source's answer with.
  @bitcoin_genesis "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f"

  @chains [
    {:bitcoin, %{halving_interval: 210_000, target_spacing: 600, genesis_hash: @bitcoin_genesis}},
    {:bitcoin_cash, %{halving_interval: 210_000, target_spacing: 600, genesis_hash: nil}},
    {:litecoin, %{halving_interval: 840_000, target_spacing: 150, genesis_hash: nil}}
  ]

  @constants Map.new(@chains)
  @atoms Enum.map(@chains, &elem(&1, 0))
  @by_name Map.new(@atoms, &{Atom.to_string(&1), &1})

  # ADR-0059 §2, §3: the one chain with a source in that record.
  @with_source [:bitcoin]

  @doc "The registered chains, in the registry's order."
  @spec chains() :: [chain()]
  def chains, do: @atoms

  @doc "The registered chains as strings (the API and MCP vocabulary)."
  @spec names() :: [String.t()]
  def names, do: Enum.map(@atoms, &Atom.to_string/1)

  @doc """
  The chain a name or atom stands for, mapped through the known list:
  `{:ok, chain}`, or `:error` for anything not registered. A string never
  becomes an atom here.
  """
  @spec fetch(term()) :: {:ok, chain()} | :error
  def fetch(chain) when chain in @atoms, do: {:ok, chain}
  def fetch(name) when is_binary(name), do: Map.fetch(@by_name, name)
  def fetch(_other), do: :error

  @doc "The subsidy halving interval of `chain`, in blocks."
  @spec halving_interval(chain()) :: pos_integer()
  def halving_interval(chain) when chain in @atoms, do: @constants[chain].halving_interval

  @doc "The protocol's target block spacing of `chain`, in seconds."
  @spec target_spacing(chain()) :: pos_integer()
  def target_spacing(chain) when chain in @atoms, do: @constants[chain].target_spacing

  @doc "The genesis block hash of a chain with a source, `nil` otherwise."
  @spec genesis_hash(chain()) :: String.t() | nil
  def genesis_hash(chain) when chain in @atoms, do: @constants[chain].genesis_hash

  @doc """
  Whether the app reads `chain` itself (ADR-0059 §3). On such a chain the
  chain reader is the only writer of `halving` events (ADR-0048's
  amendment, item 4).
  """
  @spec has_source?(chain()) :: boolean()
  def has_source?(chain) when chain in @atoms, do: chain in @with_source

  @doc "Whether `height` is a halving of `chain`: k × its interval, k ≥ 1."
  @spec halving_height?(chain(), term()) :: boolean()
  def halving_height?(chain, height) when chain in @atoms and is_integer(height) and height > 0,
    do: rem(height, halving_interval(chain)) == 0

  def halving_height?(_chain, _height), do: false
end
