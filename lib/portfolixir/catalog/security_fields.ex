defmodule Portfolixir.Catalog.SecurityFields do
  @moduledoc """
  Single source of truth for every Security attribute that can be shown in the
  list, picked in the column popover, filtered, or sorted.

  Adding a new field requires only adding an entry here. New JSONB-backed
  fields appear in the column picker and filter dialog automatically. Adding
  a new DB column still needs a migration and a schema entry, but Tabelle/
  Picker pick it up via this registry.
  """

  alias Portfolixir.Catalog.AssetClasses
  alias Portfolixir.Catalog.Currencies
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Catalog.SecurityWithMetrics

  defmodule Field do
    @moduledoc false
    @enforce_keys [:key, :label, :type, :source, :group]
    defstruct [
      :key,
      :label,
      :type,
      :source,
      :group,
      enum_values: nil,
      default_visible?: false,
      sortable?: true,
      filterable?: true,
      operators: [],
      render_hint: :text
    ]
  end

  @ops_by_type %{
    string: [:eq, :neq, :contains, :starts_with],
    enum: [:eq, :neq],
    integer: [:eq, :neq, :gt, :lt],
    decimal: [:eq, :neq, :gt, :lt],
    date: [:eq, :neq, :gt, :lt],
    boolean: [:is_true, :is_false]
  }

  def fields do
    [
      build(:name, :string, :column, :stammdaten,
        default_visible?: true,
        label: "Name"
      ),
      build(:ticker_symbol, :string, :column, :stammdaten,
        default_visible?: true,
        label: "Ticker"
      ),
      build(:isin, :string, :column, :stammdaten,
        default_visible?: true,
        label: "ISIN"
      ),
      build(:wkn, :string, :column, :stammdaten, label: "WKN"),
      build(:currency_code, :enum, :column, :stammdaten,
        default_visible?: true,
        label: "Currency",
        render_hint: :currency,
        enum_values: Currencies.codes()
      ),
      build(:exchange_code, :string, :column, :stammdaten, label: "Exchange"),
      build(:asset_class, :enum, :column, :stammdaten,
        default_visible?: true,
        label: "Asset class",
        render_hint: :badge,
        enum_values: AssetClasses.codes()
      ),
      build(:is_retired, :boolean, :column, :stammdaten,
        label: "Retired",
        render_hint: :checkbox
      ),
      # Derived from quote history (see Portfolixir.Catalog.Quotes.attach_metrics/1).
      # Not filterable in v1 — sorting client-side after enrichment.
      build(:latest_price, :decimal, :metric, :kurse,
        default_visible?: true,
        label: "Latest price",
        render_hint: :money,
        sortable?: true,
        filterable?: false
      ),
      build(:latest_price_date, :date, :metric, :kurse,
        label: "Latest price date",
        render_hint: :date,
        sortable?: true,
        filterable?: false
      ),
      build(:day_change_abs, :decimal, :metric, :kurse,
        label: "Day change",
        render_hint: :money_signed,
        sortable?: true,
        filterable?: false
      ),
      build(:day_change_pct, :decimal, :metric, :kurse,
        default_visible?: true,
        label: "Day change %",
        render_hint: :percent_signed,
        sortable?: true,
        filterable?: false
      ),
      build(:performance_1m, :decimal, :metric, :kurse,
        label: "1M performance",
        render_hint: :percent_signed,
        sortable?: true,
        filterable?: false
      ),
      build(:performance_1y, :decimal, :metric, :kurse,
        label: "1Y performance",
        render_hint: :percent_signed,
        sortable?: true,
        filterable?: false
      ),
      build(:note, :string, :column, :sonstiges,
        label: "Note",
        sortable?: false,
        filterable?: false
      ),
      # Online-source columns: visible in picker but NOT filterable —
      # filters mirror what Portfolio Performance offers in its UI.
      build(:provider, :enum, :column, :online_quelle,
        label: "Provider",
        render_hint: :badge,
        filterable?: false,
        enum_values: Security.providers()
      ),
      build(:online_id, :string, :column, :online_quelle,
        label: "Online ID",
        filterable?: false
      ),
      build(:feed, :string, :column, :online_quelle,
        label: "Quote feed",
        render_hint: :code,
        filterable?: false
      ),
      build(:feed_url, :string, :column, :online_quelle,
        label: "Quote feed URL",
        sortable?: false,
        filterable?: false
      ),
      build(:latest_feed, :string, :column, :online_quelle,
        label: "Latest quote feed",
        render_hint: :code,
        filterable?: false
      ),
      build(:latest_feed_url, :string, :column, :online_quelle,
        label: "Latest quote URL",
        sortable?: false,
        filterable?: false
      ),
      # JSONB-backed example fields. Add more entries here when providers
      # surface new attributes — they automatically appear in the column
      # picker. Filtering on attributes is intentionally off in v1.
      build({:attributes, "exchange_name"}, :string, :attributes, :online_quelle,
        label: "Exchange name",
        filterable?: false
      ),
      build({:attributes, "market_url"}, :string, :attributes, :online_quelle,
        label: "Market URL",
        sortable?: false,
        filterable?: false
      ),
      build({:attributes, "market_cap_rank"}, :integer, :attributes, :online_quelle,
        label: "Market cap rank",
        filterable?: false
      )
    ]
  end

  defp build(key_spec, type, source_kind, group, opts) do
    {key, source} =
      case key_spec do
        atom when is_atom(atom) ->
          {atom, :column}

        {:attributes, jsonb_key} ->
          {String.to_atom("attr_" <> jsonb_key), {:attributes, jsonb_key}}
      end

    source =
      case source_kind do
        :column -> :column
        :attributes -> source
        :metric -> :metric
      end

    %Field{
      key: key,
      label: Keyword.fetch!(opts, :label),
      type: type,
      source: source,
      group: group,
      enum_values: Keyword.get(opts, :enum_values),
      default_visible?: Keyword.get(opts, :default_visible?, false),
      sortable?: Keyword.get(opts, :sortable?, true),
      filterable?: Keyword.get(opts, :filterable?, true),
      operators: Keyword.get(opts, :operators, Map.fetch!(@ops_by_type, type)),
      render_hint: Keyword.get(opts, :render_hint, :text)
    }
  end

  def all, do: fields()

  def get(key) when is_atom(key) do
    Enum.find(fields(), fn f -> f.key == key end)
  end

  def get!(key) when is_atom(key) do
    case get(key) do
      nil -> raise ArgumentError, "unknown security field: #{inspect(key)}"
      field -> field
    end
  end

  def visible_default do
    fields()
    |> Enum.filter(& &1.default_visible?)
    |> Enum.map(& &1.key)
  end

  def filterable do
    Enum.filter(fields(), & &1.filterable?)
  end

  def sortable do
    Enum.filter(fields(), & &1.sortable?)
  end

  @doc "Whether a column supports gt/lt comparisons in DB (column-backed numerics/dates only)."
  def supports_range?(%Field{} = field) do
    field.source == :column and field.type in [:integer, :decimal, :date]
  end

  @doc "Pulls the field value from a Security row, honoring :column vs {:attributes, key} vs :metric."
  def value(%Field{source: :column, key: key}, %Security{} = security) do
    Map.get(security, key)
  end

  def value(%Field{source: :column, key: key}, %SecurityWithMetrics{security: security}) do
    Map.get(security, key)
  end

  def value(%Field{source: {:attributes, jsonb_key}}, %Security{attributes: attrs}) do
    Map.get(attrs || %{}, jsonb_key)
  end

  def value(%Field{source: {:attributes, jsonb_key}}, %SecurityWithMetrics{security: security}) do
    Map.get(security.attributes || %{}, jsonb_key)
  end

  def value(%Field{source: :metric, key: key}, %SecurityWithMetrics{metrics: metrics}) do
    Map.get(metrics, key)
  end

  def value(%Field{source: :metric}, %Security{}), do: nil

  @doc """
  Returns true if (key, op) is an allowed filter combination given the field's type.
  Numeric/date `gt`/`lt` against JSONB-backed fields are rejected in v1.
  """
  def valid_filter?(key, op, _value) when is_atom(key) and is_atom(op) do
    case get(key) do
      nil ->
        false

      %Field{filterable?: false} ->
        false

      %Field{operators: ops} = field ->
        op in ops and not jsonb_range_block?(field, op)
    end
  end

  def valid_filter?(_key, _op, _value), do: false

  defp jsonb_range_block?(%Field{source: {:attributes, _}}, op)
       when op in [:gt, :lt],
       do: true

  defp jsonb_range_block?(_field, _op), do: false

  def valid_sort?(key) when is_atom(key) do
    case get(key) do
      %Field{sortable?: true} -> true
      _ -> false
    end
  end
end
