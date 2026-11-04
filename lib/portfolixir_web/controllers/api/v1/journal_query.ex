defmodule PortfolixirWeb.Api.V1.JournalQuery do
  @moduledoc """
  The one reading of the audit journal's filters and page (FR-28, ADR-0017),
  shared by `GET /api/v1/journal` and the Audit journal page (Sprint 23 V3,
  idea U2): both take the same parameters — `resource_type`, `resource_id`,
  `actor_type`, `operation`, `include_scenarios`, `since` and `limit` — and
  answer the same rows, so a link the agent hands over opens the slice it
  read.

  `since` (Sprint 24 J2 and J3, decision D-4) is read by
  `SinceParam.parse_page/1`, as every paged delta read takes it (K17): a
  date, an instant, or the cursor a full page answered as `as_of`. It keeps
  the entries strictly after the cut. The API answers them oldest first, as
  a paged delta; the page shows the same rows newest first.

  The rows come from `Portfolixir.Journal.list_entries/1`; the page is
  `ListLimit`'s (#771, #1254): one row past the limit tells a cut answer
  from the whole.
  """

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Journal.Entry
  alias PortfolixirWeb.Api.V1.ListLimit
  alias PortfolixirWeb.Api.V1.SinceParam
  alias PortfolixirWeb.Api.V1.TextParam

  # #811: the bound is the family's, spelled the family's way.
  @default_limit 100
  @max_limit 1000

  @doc "The page an answer holds when no `limit` is given."
  @spec default_limit() :: pos_integer()
  def default_limit, do: @default_limit

  @doc "The largest page an answer holds; a larger `limit` is capped to it."
  @spec max_limit() :: pos_integer()
  def max_limit, do: @max_limit

  @doc """
  Parses the read's parameters: `{:ok, opts}` for `list/1`, or
  `{:error, field}` naming the first parameter that is not valid.
  """
  @spec parse(map()) :: {:ok, keyword()} | {:error, atom()}
  def parse(params) when is_map(params) do
    with {:ok, resource_type} <- text_param(params, "resource_type"),
         {:ok, resource_id} <- text_param(params, "resource_id"),
         {:ok, actor_type} <- enum_param(params, "actor_type", Actor.types()),
         {:ok, operation} <- enum_param(params, "operation", Entry.operations()),
         {:ok, since} <- SinceParam.parse_page(params),
         {:ok, limit} <- ListLimit.parse(params, @default_limit, @max_limit) do
      opts =
        [limit: limit, include_scenarios: params["include_scenarios"] == "true"]
        |> put_if_present(:resource_type, resource_type)
        |> put_if_present(:resource_id, resource_id)
        |> put_if_present(:actor_type, actor_type)
        |> put_if_present(:operation, operation)
        |> put_if_present(:since, since)

      {:ok, opts}
    end
  end

  @doc """
  The entries `opts` select, at most `opts[:limit]` of them, and whether
  more matched than the page holds: newest first (`:desc`, the default and
  the page's order), or oldest first (`:asc`, the API's paged delta under
  `since`), so a page of either order holds the rows its order reaches
  first.
  """
  @spec list(keyword(), :desc | :asc) :: {[Entry.t()], boolean()}
  def list(opts, order \\ :desc) when is_list(opts) and order in [:desc, :asc] do
    limit = Keyword.fetch!(opts, :limit)

    opts
    |> Keyword.put(:limit, ListLimit.fetch(limit))
    |> Keyword.put(:order, order)
    |> Keyword.update(:since, nil, &(&1 && SinceParam.cursor(&1)))
    |> Journal.list_entries()
    |> ListLimit.page(limit)
  end

  # The text rule every writer meets (TextParam, G24 review round).
  defp text_param(params, key) do
    case TextParam.parse(params, key) do
      {:ok, text} -> {:ok, text}
      :error -> {:error, String.to_existing_atom(key)}
    end
  end

  # Accepts a closed-enum string and maps it to its atom without
  # `String.to_atom` (no atom-table growth from untrusted input).
  defp enum_param(params, key, allowed) do
    case Map.get(params, key) do
      value when value in [nil, ""] ->
        {:ok, nil}

      value ->
        case Enum.find(allowed, fn atom -> Atom.to_string(atom) == value end) do
          nil -> {:error, String.to_existing_atom(key)}
          atom -> {:ok, atom}
        end
    end
  end

  defp put_if_present(opts, _key, value) when value in [nil, ""], do: opts
  defp put_if_present(opts, key, value), do: Keyword.put(opts, key, value)
end
