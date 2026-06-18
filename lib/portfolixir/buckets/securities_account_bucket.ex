defmodule Portfolixir.Buckets.SecuritiesAccountBucket do
  @moduledoc """
  Link row assigning a default `bucket` to a securities account (depot), part of
  the depot-default bucket set (ADR-0018). Positions in the depot inherit this
  set unless they carry their own override.
  """
  use Ecto.Schema

  alias Portfolixir.Buckets.Bucket
  alias Portfolixir.Portfolios.SecuritiesAccount

  @type t :: %__MODULE__{}

  schema "securities_account_buckets" do
    belongs_to(:securities_account, SecuritiesAccount)
    belongs_to(:bucket, Bucket)
  end
end
