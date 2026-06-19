defmodule Portfolixir.Buckets.ViewIncludeBucket do
  @moduledoc """
  Link row placing a `bucket` in a view's include set (ADR-0018). Empty include
  set with `include_all = false` means the view includes nothing on its own.
  Not journaled (view definition).
  """
  use Ecto.Schema

  alias Portfolixir.Buckets.Bucket
  alias Portfolixir.Buckets.View

  @type t :: %__MODULE__{}

  schema "view_include_buckets" do
    belongs_to(:view, View)
    belongs_to(:bucket, Bucket)
  end
end
