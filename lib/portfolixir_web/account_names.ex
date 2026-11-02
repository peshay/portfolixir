defmodule PortfolixirWeb.AccountNames do
  @moduledoc """
  Same-named accounts told apart wherever the operator picks one (#884 F1,
  board 04b; DESIGN.md, G4b): the import preview's account lists and the
  merge flow's first step (the closing act, #328).

  Per account whose name another account of its kind also carries, the tag
  that tells it apart: the first of its features whose values print
  differently across the accounts of that name, compared as the names are. A cash account: its linked depots, its
  currency, its creation date, its number; a depot: its cash account, its
  creation date, its number. An account with a unique name carries none, and
  its label is its name.

  Two names are one where they print the same
  (`PortfolixirWeb.SecurityNames.twin_key/1`: Unicode NFC and whitespace
  runs as one space, case kept; #1152). The name guard and the import's
  resolution compare names exactly, so "Demo Depot" and "Demo  Depot" can
  both exist; the options tell them apart (ADR-0050's amendment of
  2026-10-07, point 6).

  **Twins across portfolios** (#1333, Sprint 22 board 03 ⑤): account names
  are unique per portfolio, not across portfolios. Where an account's name
  is also the name of an account of its kind in another portfolio, every
  list and filter that names it — the Accounts page, the history's account
  chips, the booking drawer's selects, Wealth's cash table — adds its
  portfolio's name (`portfolio_tags/3`, `portfolio_tag/1`,
  `with_portfolio/3`). An account whose name no other portfolio uses
  carries none. The rule is decided over every account of the instance, so
  one account reads the same on every surface whatever it lists.
  """

  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Portfolios
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.SecurityNames

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

  @type portfolio_tags :: %{
          cash: %{optional(integer()) => String.t()},
          depot: %{optional(integer()) => String.t()}
        }

  @doc """
  Per cash account and per depot whose name (compared as it prints,
  `SecurityNames.twin_key/1`) an account of its kind in another portfolio
  also carries, the name of its own portfolio (#1333). `cash_accounts` and
  `depots` are each one kind, whole, and carry `:portfolio_id`; `portfolios`
  carry `:id` and `:name`.
  """
  @spec portfolio_tags([map()], [map()], [map()]) :: portfolio_tags()
  def portfolio_tags(cash_accounts, depots, portfolios)
      when is_list(cash_accounts) and is_list(depots) and is_list(portfolios) do
    names = Map.new(portfolios, &{&1.id, &1.name})

    %{
      cash: portfolio_kind_tags(cash_accounts, names),
      depot: portfolio_kind_tags(depots, names)
    }
  end

  @doc "`portfolio_tags/3` over every account and portfolio of the instance."
  @spec load_portfolio_tags() :: portfolio_tags()
  def load_portfolio_tags do
    portfolio_tags(
      Portfolios.list_cash_accounts(),
      Portfolios.list_securities_accounts(),
      Portfolios.list_portfolios()
    )
  end

  @doc "The portfolio name `tags` gives the account `id` of `kind`, or `nil`."
  @spec portfolio_of(portfolio_tags(), :cash | :depot, integer()) :: String.t() | nil
  def portfolio_of(tags, kind, id) when kind in [:cash, :depot], do: Map.get(tags[kind], id)

  @doc """
  `account`'s name for a select's option: with its portfolio's name after a
  middle dot where `tags` gives it one ("Coupon-Depot · Anleihen").
  """
  @spec with_portfolio(portfolio_tags(), :cash | :depot, map()) :: String.t()
  def with_portfolio(tags, kind, account) do
    case portfolio_of(tags, kind, account.id) do
      nil -> account.name
      portfolio -> "#{account.name} · #{portfolio}"
    end
  end

  attr(:tags, :map, required: true, doc: "the `t:portfolio_tags/0` of the page")
  attr(:kind, :atom, required: true, values: [:cash, :depot])
  attr(:id, :integer, required: true, doc: "the account's id")

  @doc """
  The portfolio's name after a twin account's name (board 03 ⑤), the
  account `id` of `kind` looked up in `tags`: the twin
  tag's anatomy (`.twin-id`, `SecurityNames.twin_id/1`, its spacing rule
  included) in the word voice of `.twin-id--portfolio`, a visually hidden
  "Portfolio" before the name. `nil` renders nothing, not even the space.
  """
  def portfolio_tag(assigns) do
    assigns = assign(assigns, :portfolio, portfolio_of(assigns.tags, assigns.kind, assigns.id))

    ~H"""
    <%= if @portfolio do %><%= " " %><span class="twin-id twin-id--portfolio"><span class="visually-hidden"><%= gettext("Portfolio") %></span><%= " " %><%= @portfolio %></span><% end %>
    """
  end

  defp portfolio_kind_tags(accounts, portfolio_names) do
    accounts
    |> Enum.group_by(&SecurityNames.twin_key(&1.name))
    |> Enum.flat_map(fn {_name, same} ->
      if same |> Enum.uniq_by(& &1.portfolio_id) |> length() > 1 do
        Enum.map(same, &{&1.id, Map.get(portfolio_names, &1.portfolio_id, "—")})
      else
        []
      end
    end)
    |> Map.new()
  end

  defp kind_tags(accounts, features) do
    accounts
    |> Enum.group_by(&SecurityNames.twin_key(&1.name))
    |> Enum.flat_map(fn
      {_name, [_single]} ->
        []

      {_name, same} ->
        # A feature tells the twins apart only where its values print
        # differently, compared as the names are (#1152): two tags that read
        # the same would stand for two accounts.
        feature =
          Enum.find(features, List.last(features), fn feature ->
            values = Enum.map(same, feature)
            length(Enum.uniq_by(values, &SecurityNames.twin_key/1)) == length(values)
          end)

        Enum.map(same, &{&1.id, feature.(&1)})
    end)
    |> Map.new()
  end

  defp created_tag(account),
    do:
      gettext("created %{date}",
        date: account.inserted_at |> NaiveDateTime.to_date() |> Format.date()
      )

  defp number_tag(account), do: gettext("no. %{id}", id: account.id)
end
