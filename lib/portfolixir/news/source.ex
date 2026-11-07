defmodule Portfolixir.News.Source do
  @moduledoc """
  A news source (ADR-0056 §3): one domain and its tier — `primary`,
  `secondary`, `awareness` or `blocked`. An unknown domain reads as
  `awareness` until someone rates it; that default is the reader's, not a
  stored row.

  `set_by` records who set the tier: `hand` (the operator or the agent,
  through the API) or `seed`. **A correction by hand is never overwritten by
  a later import or seed** (§3, the invariant ADR-0044 §2 binds for
  `source_quality`): a seeding writer leaves a `hand` row as it is. The
  domain is stored trimmed and lower-case and is unique.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Input.Text
  alias Portfolixir.News.Shapes

  @type t :: %__MODULE__{}

  schema "news_sources" do
    field(:domain, :string)
    field(:tier, Ecto.Enum, values: Shapes.tiers())
    field(:set_by, Ecto.Enum, values: [:hand, :seed])

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Casts and checks a source's domain, tier and who set it."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(source, attrs) do
    source
    |> cast(attrs, [:domain, :tier, :set_by])
    |> validate_required([:domain, :tier, :set_by])
    |> Text.validate(:domain, max: 253)
    |> Shapes.domain(:domain)
    |> unique_constraint(:domain, name: :news_sources_domain_index)
    |> check_constraint(:domain, name: :news_sources_domain_check, message: "is invalid")
    |> check_constraint(:tier, name: :news_sources_tier_check, message: "is invalid")
    |> check_constraint(:set_by, name: :news_sources_set_by_check, message: "is invalid")
  end
end
