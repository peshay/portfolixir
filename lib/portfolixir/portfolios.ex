defmodule Portfolixir.Portfolios do
  @moduledoc "Portfolio context."

  alias Portfolixir.Portfolios.Portfolio
  alias Portfolixir.Repo

  def list_portfolios do
    Repo.all(Portfolio)
  end

  def get_portfolio!(id) do
    Repo.get!(Portfolio, id)
  end

  def create_portfolio(attrs) when is_map(attrs) do
    %Portfolio{}
    |> Portfolio.changeset(attrs)
    |> Repo.insert()
  end

  def update_portfolio(%Portfolio{} = portfolio, attrs) when is_map(attrs) do
    portfolio
    |> Portfolio.changeset(attrs)
    |> Repo.update()
  end

  def delete_portfolio(%Portfolio{} = portfolio) do
    Repo.delete(portfolio)
  end
end
