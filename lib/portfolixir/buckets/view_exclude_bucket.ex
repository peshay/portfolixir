defmodule Portfolixir.Buckets.ViewExcludeBucket do
  @moduledoc """
  Link row placing a `bucket` in a view's exclude set (ADR-0018). Exclude always
  wins over include. Not journaled (view definition).
  """
  use Ecto.Schema

  alias Portfolixir.Buckets.Bucket
  alias Portfolixir.Buckets.View

  @type t :: %__MODULE__{}

  schema "view_exclude_buckets" do
    belongs_to(:view, View)
    belongs_to(:bucket, Bucket)
  end
end
