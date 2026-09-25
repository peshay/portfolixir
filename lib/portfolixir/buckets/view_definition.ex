defmodule Portfolixir.Buckets.ViewDefinition do
  @moduledoc """
  A view's whole definition as the audit journal records it (E25 S6, F45):
  the `views` row and both of its bucket sets, sorted.

  A policy rule in force reads a view (ADR-0049 §1), so what the view
  includes is part of what the rule's finding means. The row alone would not
  say it — the sets live in `view_include_buckets` and
  `view_exclude_buckets` — so a view-definition write journals this
  aggregate, filed under the view's id, as its before- and after-image.
  """

  import Ecto.Query

  alias Portfolixir.Buckets.View
  alias Portfolixir.Buckets.ViewExcludeBucket
  alias Portfolixir.Buckets.ViewIncludeBucket

  defstruct [
    :id,
    :name,
    :include_all,
    :source_portfolio_id,
    :inserted_at,
    :updated_at,
    include_bucket_ids: [],
    exclude_bucket_ids: []
  ]

  @type t :: %__MODULE__{}

  @doc "The definition of a stored view: the row and both sets, sorted."
  @spec of(Ecto.Repo.t(), View.t()) :: t()
  def of(repo, %View{} = view) do
    %__MODULE__{
      id: view.id,
      name: view.name,
      include_all: view.include_all,
      source_portfolio_id: view.source_portfolio_id,
      inserted_at: view.inserted_at,
      updated_at: view.updated_at,
      include_bucket_ids: bucket_ids(repo, ViewIncludeBucket, view.id),
      exclude_bucket_ids: bucket_ids(repo, ViewExcludeBucket, view.id)
    }
  end

  defp bucket_ids(repo, schema, view_id) do
    repo.all(
      from(x in schema, where: x.view_id == ^view_id, order_by: x.bucket_id, select: x.bucket_id)
    )
  end
end
