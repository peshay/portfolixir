defmodule Portfolixir.Buckets.CashAccountBucket do
  @moduledoc """
  Link row assigning a `bucket` to a cash account. Cash accounts are bucketable
  in their own right (ADR-0018); a cash account's effective buckets are exactly
  its assigned set.
  """
  use Ecto.Schema

  alias Portfolixir.Buckets.Bucket
  alias Portfolixir.Portfolios.CashAccount

  @type t :: %__MODULE__{}

  schema "cash_account_buckets" do
    belongs_to(:cash_account, CashAccount)
    belongs_to(:bucket, Bucket)
  end
end
