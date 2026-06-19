defmodule Portfolixir.Buckets.PositionBucketOverride do
  @moduledoc """
  Per-position bucket override, keyed on `(securities_account_id, security_id)`
  because holdings are derived and never stored (ADR-0004, ADR-0018).

  Encoding of the three assignment states for a position:

    * **inherit** — no override rows: the position uses its depot's default set.
    * **explicit-empty** — exactly one row with `bucket_id == nil`: the position
      deliberately has no buckets (distinct from inherit).
    * **explicit set** — one row per assigned bucket (`bucket_id` set).

  A `NULLS NOT DISTINCT` unique index keeps the explicit-empty marker singular.
  """
  use Ecto.Schema

  alias Portfolixir.Buckets.Bucket
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Portfolios.SecuritiesAccount

  @type t :: %__MODULE__{}

  schema "position_bucket_overrides" do
    belongs_to(:securities_account, SecuritiesAccount)
    belongs_to(:security, Security)
    belongs_to(:bucket, Bucket)
  end
end
