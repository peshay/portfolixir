defmodule Portfolixir.Catalog do
  @moduledoc "Currency and security catalogue context."

  import Ecto.Query
  alias Portfolixir.Catalog.Currency
  alias Portfolixir.Catalog.Security
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

  def create_security(attrs) when is_map(attrs) do
    %Security{}
    |> Security.changeset(attrs)
    |> Repo.insert()
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

  def delete_security(%Security{} = security) do
    Repo.delete(security)
  end

  def ensure_mvp_currencies! do
    Enum.each(@mvp_currencies, fn attrs ->
      case get_currency_by_code(attrs.code) do
        nil ->
          {:ok, _currency} = create_currency(attrs)

        _currency ->
          {:ok, :already_exists}
      end
    end)
  end

  def seed_mvp_currencies!, do: ensure_mvp_currencies!()
end
