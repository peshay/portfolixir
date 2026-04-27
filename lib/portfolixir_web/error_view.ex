defmodule PortfolixirWeb.ErrorView do
  def render("500.json", _assigns) do
    %{status: 500, error: "Internal Server Error"}
  end

  def render("404.json", _assigns) do
    %{status: 404, error: "Not Found"}
  end

  def template_not_found(_template, _assigns) do
    %{error: "Not Found"}
  end
end
