defmodule Portfolixir.Catalog do
  @moduledoc "Currency and security catalogue context."

  import Ecto.Query
  alias Portfolixir.Catalog.Currency
  alias Portfolixir.Catalog.FundAllocation
  alias Portfolixir.Catalog.FundAllocationItem
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Catalog.FundDocument
  alias Portfolixir.Catalog.SecurityQuote
  alias Portfolixir.Catalog.SecurityCategoryAssignment
  alias Portfolixir.Repo
  alias Portfolixir.Taxonomies.Category

  @mvp_currencies [
    %{code: "EUR", name: "Euro", minor_units: 2},
    %{code: "USD", name: "US Dollar", minor_units: 2},
    %{code: "CHF", name: "Swiss Franc", minor_units: 2},
    %{code: "GBP", name: "British Pound", minor_units: 2},
    %{code: "SEK", name: "Swedish Krona", minor_units: 2},
    %{code: "NOK", name: "Norwegian Krone", minor_units: 2},
    %{code: "DKK", name: "Danish Krone", minor_units: 2},
    %{code: "JPY", name: "Japanese Yen", minor_units: 0}
  ]

  def list_currencies do
    from(c in Currency, order_by: [asc: c.code])
    |> Repo.all()
  end

  def get_currency!(code) when is_binary(code) do
    Repo.get_by!(Currency, code: code)
  end

  def get_currency_by_code(code) when is_binary(code) do
    Repo.get_by(Currency, code: code)
  end

  def create_currency(attrs) when is_map(attrs) do
    %Currency{}
    |> Currency.changeset(attrs)
    |> Repo.insert()
  end

  def ensure_currency(attrs) when is_map(attrs) do
    code = Map.fetch!(attrs, :code)

    case Repo.insert(
           %Currency{}
           |> Currency.changeset(attrs),
           on_conflict: :nothing,
           conflict_target: :code,
           returning: true
         ) do
      {:ok, currency} ->
        {:ok, currency}

      {:error, changeset} ->
        case get_currency_by_code(code) do
          nil -> {:error, changeset}
          currency -> {:ok, currency}
        end
    end
  end

  @doc """
  List securities by status.
  """
  def list_securities(status \\ :active)

  def list_securities(status) when status in [:active, :inactive, :all] do
    from(s in Security, order_by: [asc: s.name, asc: s.symbol])
    |> filter_by_status(status)
    |> Repo.all()
  end

  defp filter_by_status(query, :all), do: query
  defp filter_by_status(query, :active), do: where(query, [s], s.active == true)
  defp filter_by_status(query, :inactive), do: where(query, [s], s.active == false)

  def get_security!(id), do: Repo.get!(Security, id)
  def get_security(id) when is_integer(id), do: Repo.get(Security, id)

  def get_security(id) when is_binary(id) do
    case Integer.parse(id) do
      {security_id, ""} -> Repo.get(Security, security_id)
      _ -> nil
    end
  end

  def get_security(_), do: nil

  def create_security(attrs) when is_map(attrs) do
    %Security{}
    |> Security.changeset(attrs)
    |> Repo.insert()
  end

  def create_security_quote(attrs) when is_map(attrs) do
    %SecurityQuote{}
    |> SecurityQuote.changeset(attrs)
    |> Repo.insert()
  end

  def list_security_quotes(security_id) when is_integer(security_id),
    do: list_security_quotes(security_id, [])

  def list_security_quotes(security_id, opts) when is_integer(security_id) and is_list(opts) do
    opts = Map.new(opts)

    from(sq in SecurityQuote,
      where: sq.security_id == ^security_id,
      order_by: [asc: sq.date]
    )
    |> maybe_filter_from(Map.get(opts, :from))
    |> maybe_filter_to(Map.get(opts, :to))
    |> Repo.all()
  end

  def list_security_quotes(security_id, opts) when is_integer(security_id) and is_map(opts) do
    list_security_quotes(security_id, Map.to_list(opts))
  end

  def get_latest_security_quote(security_id) when is_integer(security_id) do
    Repo.one(
      from(sq in SecurityQuote,
        where: sq.security_id == ^security_id,
        order_by: [desc: sq.date, desc: sq.id],
        limit: 1
      )
    )
  end

  def upsert_security_quote(attrs) when is_map(attrs) do
    %SecurityQuote{}
    |> SecurityQuote.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:open, :high, :low, :close, :volume, :metadata, :currency_code]},
      conflict_target: [:security_id, :source, :date]
    )
  end

  def create_fund_allocation(attrs) when is_map(attrs) do
    %FundAllocation{}
    |> FundAllocation.changeset(attrs)
    |> Repo.insert()
  end

  def list_fund_allocations_for_report do
    from(fa in FundAllocation,
      join: security in assoc(fa, :security),
      where: fa.status == "active",
      order_by: [
        asc: security.name,
        asc: fa.allocation_type,
        asc: fragment("CASE WHEN ? IS NULL THEN 1 ELSE 0 END", fa.as_of_date),
        desc: fa.as_of_date
      ],
      preload: [
        :security,
        fund_allocation_items:
          ^from(i in FundAllocationItem, order_by: [desc: i.weight, asc: i.label])
      ]
    )
    |> Repo.all()
  end

  def list_fund_allocations_for_security(security_id) when is_integer(security_id) do
    from(fa in FundAllocation,
      where: fa.security_id == ^security_id,
      order_by: [asc: fa.allocation_type, asc: fa.source, asc: fa.inserted_at]
    )
    |> Repo.all()
  end

  def get_fund_allocation!(id), do: Repo.get!(FundAllocation, id)

  def count_fund_allocations do
    Repo.aggregate(FundAllocation, :count, :id)
  end

  def create_fund_allocation_item(attrs) when is_map(attrs) do
    %FundAllocationItem{}
    |> FundAllocationItem.changeset(attrs)
    |> Repo.insert()
  end

  def create_fund_document(attrs) when is_map(attrs) do
    %FundDocument{}
    |> FundDocument.changeset(attrs)
    |> Repo.insert()
  end

  def list_fund_allocation_items(fund_allocation_id) when is_integer(fund_allocation_id) do
    from(fai in FundAllocationItem,
      where: fai.fund_allocation_id == ^fund_allocation_id,
      order_by: [asc: fai.label, asc: fai.inserted_at]
    )
    |> Repo.all()
  end

  def list_recent_fund_documents(limit \\ 20)

  def list_recent_fund_documents(limit) when is_integer(limit) do
    Repo.all(
      from(fd in FundDocument,
        order_by: [desc: fd.inserted_at, desc: fd.id],
        preload: [:security],
        limit: ^limit
      )
    )
  end

  def list_recent_fund_documents(_invalid_limit), do: []

  def count_fund_documents do
    Repo.aggregate(FundDocument, :count, :id)
  end

  def list_fund_documents_for_security(security_id) when is_integer(security_id) do
    from(fd in FundDocument,
      where: fd.security_id == ^security_id,
      order_by: [desc: fd.inserted_at, desc: fd.id]
    )
    |> Repo.all()
  end

  def get_fund_document!(id) when is_integer(id), do: Repo.get!(FundDocument, id)

  def get_fund_document_for_security_and_hash(security_id, content_hash)
      when is_integer(security_id) and is_binary(content_hash) do
    Repo.get_by(FundDocument, security_id: security_id, content_hash: content_hash)
  end

  def assign_category_to_security(security_id, category_id)
      when is_integer(security_id) and is_integer(category_id) do
    %SecurityCategoryAssignment{}
    |> SecurityCategoryAssignment.changeset(%{security_id: security_id, category_id: category_id})
    |> Repo.insert()
  end

  def list_security_categories(security_id) when is_integer(security_id) do
    Repo.all(
      from(c in Category,
        join: assignment in SecurityCategoryAssignment,
        on: assignment.category_id == c.id,
        where: assignment.security_id == ^security_id,
        order_by: [asc: c.name]
      )
    )
  end

  def remove_category_assignment(security_id, category_id)
      when is_integer(security_id) and is_integer(category_id) do
    security_category_assignment =
      Repo.one(
        from(a in SecurityCategoryAssignment,
          where: a.security_id == ^security_id and a.category_id == ^category_id
        )
      )

    case security_category_assignment do
      nil ->
        {:error, :not_found}

      %SecurityCategoryAssignment{} = assignment ->
        Repo.delete(assignment)
    end
  end

  def update_security(%Security{} = security, attrs) when is_map(attrs) do
    security
    |> Security.changeset(attrs)
    |> Repo.update()
  end

  def archive_security(%Security{} = security) do
    update_security(security, %{active: false})
  end

  def delete_security(%Security{} = security) do
    Repo.delete(security)
  end

  def ensure_mvp_currencies! do
    Enum.each(@mvp_currencies, fn attrs ->
      {:ok, _currency} = ensure_currency(attrs)
    end)
  end

  def seed_mvp_currencies!, do: ensure_mvp_currencies!()

  defp maybe_filter_from(query, %Date{} = from_date) do
    where(query, [sq], sq.date >= ^from_date)
  end

  defp maybe_filter_from(query, _), do: query

  defp maybe_filter_to(query, %Date{} = to_date) do
    where(query, [sq], sq.date <= ^to_date)
  end

  defp maybe_filter_to(query, _), do: query
end
