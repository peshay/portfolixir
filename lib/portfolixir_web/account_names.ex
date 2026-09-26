defmodule PortfolixirWeb.AccountNames do
  @moduledoc """
  Same-named accounts told apart wherever the operator picks one (#884 F1,
  board 04b; DESIGN.md, G4b): the import preview's account lists and the
  merge flow's first step (the closing act, #328).

  Per account whose name another account of its kind also carries, the tag
  that tells it apart: the first of its features whose values differ across
  the accounts of that name. A cash account: its linked depots, its
  currency, its creation date, its number; a depot: its cash account, its
  creation date, its number. An account with a unique name carries none, and
  its label is its name.
  """

  use Gettext, backend: PortfolixirWeb.Gettext

  @type tags :: %{
          cash: %{optional(integer()) => String.t()},
          depot: %{optional(integer()) => String.t()}
        }

  @doc """
  The tags of every same-named cash account and depot, read over all
  `cash_accounts` and `depots` (each list one kind, whole).
  """
  @spec tags([map()], [map()]) :: tags()
  def tags(cash_accounts, depots) when is_list(cash_accounts) and is_list(depots) do
    depots_by_cash = Enum.group_by(depots, & &1.cash_account_id, & &1.name)
    cash_names = Map.new(cash_accounts, &{&1.id, &1.name})

    cash_features = [
      fn c ->
        case depots_by_cash |> Map.get(c.id, []) |> Enum.sort() do
          [] -> gettext("no depot")
          names -> gettext("at %{depots}", depots: Enum.join(names, ", "))
        end
      end,
      & &1.currency_code,
      &created_tag/1,
      &number_tag/1
    ]

    depot_features = [
      &gettext("with %{cash}", cash: Map.get(cash_names, &1.cash_account_id, "—")),
      &created_tag/1,
      &number_tag/1
    ]

    %{cash: kind_tags(cash_accounts, cash_features), depot: kind_tags(depots, depot_features)}
  end

  @doc "`account`'s name, with its tag after a middle dot when `tags` gives it one."
  @spec label(tags(), :cash | :depot, map()) :: String.t()
  def label(tags, kind, account) when kind in [:cash, :depot] do
    case Map.get(tags[kind], account.id) do
      nil -> account.name
      tag -> "#{account.name} · #{tag}"
    end
  end

  defp kind_tags(accounts, features) do
    accounts
    |> Enum.group_by(& &1.name)
    |> Enum.flat_map(fn
      {_name, [_single]} ->
        []

      {_name, same} ->
        feature =
          Enum.find(features, List.last(features), fn feature ->
            values = Enum.map(same, feature)
            length(Enum.uniq(values)) == length(values)
          end)

        Enum.map(same, &{&1.id, feature.(&1)})
    end)
    |> Map.new()
  end

  defp created_tag(account),
    do:
      gettext("created %{date}",
        date: account.inserted_at |> NaiveDateTime.to_date() |> Date.to_iso8601()
      )

  defp number_tag(account), do: gettext("no. %{id}", id: account.id)
end
