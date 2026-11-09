defmodule PortfolixirWeb.Api.V1.BandsParam do
  @moduledoc """
  Shared parsing for the bands reads (I23, FR-53): `level`, `sort`,
  `classification_id` and `category_id`, read strictly. A value outside its
  set, or an id that is malformed, is refused naming the parameter; the
  values map onto atoms by an explicit whitelist, never `String.to_atom/1`
  (AGENTS.md). `category_id` is the filter at every level (FR-56): a
  category's id, or exactly `unclassified` for the securities the tree files
  nowhere.
  """

  alias Portfolixir.Catalog.Currencies
  alias PortfolixirWeb.Api.V1.IdParam

  @levels %{"total" => :total, "category" => :category, "security" => :security}
  @filter_error "is invalid: must be a category id or unclassified"
  @sorts %{"size" => :size, "change" => :change}

  @doc """
  The keyword options for `Portfolixir.Portfolios.Performance.Bands`, or
  `{:error, errors}` with the 422 body's `errors` map.
  """
  @spec resolve(map()) :: {:ok, keyword()} | {:error, map()}
  def resolve(params) do
    with {:ok, level} <- choice(params, "level", @levels, "total, category, security"),
         {:ok, sort} <- choice(params, "sort", @sorts, "size, change"),
         {:ok, classification_id} <- id(params, "classification_id"),
         {:ok, category_id} <- filter(params) do
      {:ok,
       []
       |> put_present(:level, level)
       |> put_present(:sort, sort)
       |> put_present(:classification_id, classification_id)
       |> put_present(:category_id, category_id)}
    end
  end

  @doc """
  The view forms' `base_currency` (the closing act's money lens, M1): a code
  of `Portfolixir.Catalog.Currencies`, exactly as listed, kept a string;
  absent, the EUR hub. The portfolio form answers in its portfolio's base
  currency and takes no such parameter.
  """
  @spec base_currency(map()) :: {:ok, String.t()} | {:error, map()}
  def base_currency(params) do
    case Map.get(params, "base_currency") do
      nil ->
        {:ok, "EUR"}

      raw ->
        if Currencies.supported?(raw),
          do: {:ok, raw},
          else:
            {:error,
             %{
               "base_currency" => ["is invalid: must be a supported currency code, e.g. EUR, USD"]
             }}
    end
  end

  @doc """
  The 422 body's `errors` map for an error the bands read returns, or `nil`
  for one that is not about these parameters.
  """
  @spec errors(atom()) :: map() | nil
  def errors(:invalid_period), do: %{period: ["is invalid"]}
  def errors(:classification_not_found), do: %{classification_id: ["does not exist"]}
  def errors(:category_not_found), do: %{category_id: ["does not exist"]}

  def errors(:category_outside_classification),
    do: %{category_id: ["is not a category of classification_id"]}

  def errors(:invalid_category), do: %{category_id: [@filter_error]}

  def errors(_other), do: nil

  defp choice(params, key, allowed, names) do
    case Map.get(params, key) do
      nil ->
        {:ok, nil}

      raw ->
        case Map.fetch(allowed, raw) do
          {:ok, value} -> {:ok, value}
          :error -> {:error, %{key => ["is invalid: must be one of #{names}"]}}
        end
    end
  end

  defp filter(params) do
    case Map.get(params, "category_id") do
      nil ->
        {:ok, nil}

      "unclassified" ->
        {:ok, :unclassified}

      raw ->
        case IdParam.parse(raw) do
          {:ok, id} -> {:ok, id}
          :error -> {:error, %{"category_id" => [@filter_error]}}
        end
    end
  end

  defp id(params, key) do
    case Map.get(params, key) do
      nil ->
        {:ok, nil}

      raw ->
        case IdParam.parse(raw) do
          {:ok, id} -> {:ok, id}
          :error -> {:error, %{key => ["is invalid"]}}
        end
    end
  end

  defp put_present(opts, _key, nil), do: opts
  defp put_present(opts, key, value), do: Keyword.put(opts, key, value)
end
