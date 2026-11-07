defmodule Portfolixir.News.Universe do
  @moduledoc """
  The securities an `aggregator` item is matched against (ADR-0056 §2).

  **A member** is a security that

    * **a view holds** — read as `Portfolixir.Ledger.HeldSecurities`: a
      quantity summed over every depot of every portfolio that is not zero.
      Every held position is in the unscoped view (the whole wealth), so a
      security held anywhere is held by a view; a named view only narrows
      that set, and a security held outside every named view still deserves
      its news;
    * **carries a target weight above zero** — a position target
      (`Portfolixir.Portfolios.Target` with a `security_id`, ADR-0030) above
      zero in an **active** plan of any portfolio, view or classification. A
      category's target names no security, and a draft or archived plan is
      not in force, so neither adds one;
    * or **carries `news_watch`** — a candidate with no holding and no
      target (§2's reason for the flag).

  **Exchange-traded funds get no aggregator matching** (§2: a fund's name
  matches index and market news that is not about the fund). A fund is an
  ETF when its effective asset class is `etf`
  (`Portfolixir.Catalog.Security.effective_asset_class/1`: the class stored,
  or else the one its name implies). It stays a member — an `issuer` feed
  may still name it — and `aggregator/0` leaves it out. Other funds are
  matched: §2 names exchange-traded funds, and a fund the catalogue cannot
  tell to be one is matched until its class says so.

  The members are read on each call; nothing is cached, so an alias, a
  holding or a target written a moment ago counts at once.
  """
  import Ecto.Query

  alias Portfolixir.Catalog.Security
  alias Portfolixir.Ledger.HeldSecurities
  alias Portfolixir.News.Matcher
  alias Portfolixir.Portfolios.Target
  alias Portfolixir.Portfolios.TargetPlan
  alias Portfolixir.Repo

  @type member :: %{
          id: pos_integer(),
          name: String.t(),
          kind: String.t() | nil,
          aliases: [Portfolixir.News.Alias.t()],
          cik: String.t() | nil,
          isin: String.t() | nil,
          wkn: String.t() | nil
        }

  @doc "Every security of the universe, ordered by id."
  @spec members() :: [member()]
  def members do
    from(s in Security,
      where:
        s.news_watch or s.id in subquery(HeldSecurities.held_ids_query()) or
          s.id in subquery(targeted_ids_query()),
      order_by: s.id
    )
    |> Repo.all()
    |> Enum.map(&member/1)
  end

  @doc "The members aggregator items are matched against: every member but the ETFs."
  @spec aggregator() :: [member()]
  def aggregator, do: Enum.reject(members(), &etf?/1)

  @doc "`aggregator/0`, compiled for `Portfolixir.News.Matcher`."
  @spec aggregator_index() :: Matcher.index()
  def aggregator_index, do: Matcher.compile(aggregator())

  @doc "Whether a member is an exchange-traded fund (no aggregator matching)."
  @spec etf?(member()) :: boolean()
  def etf?(%{kind: kind}), do: kind == "etf"

  defp targeted_ids_query do
    from(t in Target,
      join: p in TargetPlan,
      on: p.id == t.plan_id,
      where: p.status == "active" and not is_nil(t.security_id) and t.target_weight > 0,
      distinct: true,
      select: t.security_id
    )
  end

  defp member(%Security{} = security) do
    %{
      id: security.id,
      name: security.name,
      kind: Security.effective_asset_class(security),
      aliases: security.news_aliases || [],
      cik: security.news_cik,
      isin: security.isin,
      wkn: security.wkn
    }
  end
end
