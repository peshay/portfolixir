defmodule Portfolixir.Catalog do
  @moduledoc "Security master data and stored quote history."

  import Ecto.Query

  alias Portfolixir.Catalog.Security
  alias Portfolixir.Catalog.SecurityQuote
  alias Portfolixir.Repo

  def list_securities do
    Repo.all(from(security in Security, order_by: [asc: security.name, asc: security.symbol]))
  end

  def count_securities do
    Repo.aggregate(Security, :count, :id)
  end

  def get_security!(id), do: Repo.get!(Security, id)

  def get_security(id) when is_integer(id), do: Repo.get(Security, id)

  def get_security(id) when is_binary(id) do
    case Integer.parse(id) do
      {security_id, ""} -> get_security(security_id)
      _invalid -> nil
    end
  end

  def get_security(_id), do: nil

  def create_security(attrs) when is_map(attrs) do
    %Security{}
    |> Security.changeset(attrs)
    |> Repo.insert()
  end

  def change_security(%Security{} = security, attrs \\ %{}) do
    Security.changeset(security, attrs)
  end

  def create_security_quote(attrs) when is_map(attrs) do
    %SecurityQuote{}
    |> SecurityQuote.changeset(attrs)
    |> Repo.insert()
  end

  def change_security_quote(%SecurityQuote{} = security_quote, attrs \\ %{}) do
    SecurityQuote.changeset(security_quote, attrs)
  end

  def list_security_quotes(security_id) when is_integer(security_id) do
    Repo.all(
      from(quote in SecurityQuote,
        where: quote.security_id == ^security_id,
        order_by: [asc: quote.date, asc: quote.id]
      )
    )
  end

  def get_latest_security_quote(security_id) when is_integer(security_id) do
    Repo.one(
      from(quote in SecurityQuote,
        where: quote.security_id == ^security_id,
        order_by: [desc: quote.date, desc: quote.id],
        limit: 1
      )
    )
  end

  def count_security_quotes do
    Repo.aggregate(SecurityQuote, :count, :id)
  end
end
