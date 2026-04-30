defmodule Portfolixir.Imports.PortfolioPerformanceXmlImport do
  @moduledoc "Confirm and persist Portfolio Performance XML previews."

  import Ecto.Query

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.{Currency, Security}
  alias Portfolixir.Imports

  alias Portfolixir.Imports.{
    ImportRun,
    ImportSource,
    PortfolioPerformanceXmlPreview,
    RawImportItem
  }

  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.DepositAccount
  alias Portfolixir.Portfolios.{Portfolio}
  alias Portfolixir.Catalog.SecurityCategoryAssignment
  alias Portfolixir.Repo
  alias Portfolixir.Taxonomies
  alias Portfolixir.Taxonomies.{Category, Taxonomy}

  @source_name "Portfolio Performance XML"
  @source_type "pp_xml"
  @source_status "active"
  @raw_content_type "application/xml"
  @raw_source_name "portfolio_performance_xml"

  @summary_sections [
    "currencies",
    "portfolios",
    "securities",
    "accounts",
    "transactions",
    "taxonomies",
    "categories",
    "assignments",
    "raw_items"
  ]

  def confirm(xml_binary_or_string)
      when is_binary(xml_binary_or_string) or is_list(xml_binary_or_string) do
    with {:ok, preview} <- PortfolioPerformanceXmlPreview.preview(xml_binary_or_string) do
      confirm_preview(preview)
    end
  end

  def confirm(preview) when is_map(preview), do: confirm_preview(preview)

  def confirm(_),
    do: {:error, {:invalid_input, "Expected XML binary/string or preview map."}}

  def confirm_preview(preview) when is_map(preview) do
    import_from_preview(preview)
  end

  defp import_from_preview(preview) when is_map(preview) do
    started_at = utc_now()

    case Repo.transaction(fn ->
           with {:ok, import_source} <- get_or_create_source(),
                {:ok, import_run} <- create_import_run(import_source, started_at),
                state =
                  build_initial_state(preview, import_source, import_run)
                  |> run_import(),
                summary = Map.put(state.summary, "import_run_id", import_run.id),
                {:ok, finished_run} <- finish_import_run(import_run, summary) do
             finished_run
           else
             {:error, reason} -> Repo.rollback(reason)
           end
         end) do
      {:ok, %ImportRun{summary: summary}} -> {:ok, summary}
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_import(state) do
    state
    |> index_currencies()
    |> process_portfolios()
    |> process_securities()
    |> process_accounts()
    |> process_taxonomies()
    |> process_categories()
    |> process_transactions()
  end

  defp base_summary do
    zeroes = Map.new(@summary_sections, &{&1, 0})

    %{
      "created" => zeroes,
      "updated" => zeroes,
      "skipped" => zeroes,
      "failed" => zeroes,
      "warnings" => []
    }
  end

  defp build_initial_state(preview, import_source, import_run) do
    %{
      preview: preview,
      import_source: import_source,
      import_run: import_run,
      summary: base_summary(),
      currencies_by_code: %{},
      portfolios_by_external_id: %{},
      securities_by_external_id: %{},
      accounts_by_external_id: %{},
      categories_by_external_id: %{},
      taxonomies_by_external_id: %{},
      primary_portfolio: nil
    }
  end

  defp get_or_create_source do
    case Repo.get_by(ImportSource,
           name: @source_name,
           type: @source_type,
           status: @source_status
         ) do
      %ImportSource{} = source ->
        {:ok, source}

      nil ->
        Imports.create_import_source(%{
          name: @source_name,
          type: @source_type,
          status: @source_status
        })
    end
  end

  defp create_import_run(import_source, started_at) do
    Imports.create_import_run(%{
      import_source_id: import_source.id,
      status: "started",
      started_at: started_at
    })
  end

  defp finish_import_run(%ImportRun{} = import_run, summary) do
    import_run
    |> ImportRun.changeset(%{
      status: "completed",
      finished_at: utc_now(),
      summary: summary
    })
    |> Repo.update()
  end

  defp index_currencies(state) do
    currencies =
      state.preview
      |> Map.get("securities", [])
      |> Enum.map(&Map.get(&1, "currency"))
      |> Kernel.++(Map.get(state.preview, "accounts", []) |> Enum.map(&Map.get(&1, "currency")))
      |> Kernel.++(
        Map.get(state.preview, "portfolios", [])
        |> Enum.map(&Map.get(&1, "base_currency"))
      )
      |> Kernel.++(
        Map.get(state.preview, "transactions", [])
        |> Enum.map(&Map.get(&1, "currency"))
      )
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    Enum.reduce(currencies, state, &ensure_currency/2)
  end

  defp ensure_currency(code, state) do
    code = trim_string(code)

    cond do
      is_nil(code) ->
        state

      Map.has_key?(state.currencies_by_code, code) ->
        state

      true ->
        case Repo.get_by(Currency, code: code) do
          %Currency{} = currency ->
            put_in(state, [:currencies_by_code, code], currency)

          nil ->
            case Catalog.create_currency(%{code: code, name: currency_name(code), minor_units: 2}) do
              {:ok, currency} ->
                state
                |> put_in([:currencies_by_code, code], currency)
                |> increment("created", "currencies")

              {:error, changeset} ->
                state
                |> increment("failed", "currencies")
                |> append_warning(
                  "Currency #{code} could not be created: #{inspect(changeset.errors)}"
                )
            end
        end
    end
  end

  defp currency_name("EUR"), do: "Euro"
  defp currency_name("USD"), do: "US Dollar"
  defp currency_name("GBP"), do: "British Pound"
  defp currency_name("CHF"), do: "Swiss Franc"
  defp currency_name("SEK"), do: "Swedish Krona"
  defp currency_name("NOK"), do: "Norwegian Krone"
  defp currency_name("DKK"), do: "Danish Krone"
  defp currency_name("JPY"), do: "Japanese Yen"
  defp currency_name(code), do: code

  defp process_portfolios(state),
    do: reduce_records(state, Map.get(state.preview, "portfolios", []), &process_portfolio/2)

  defp process_portfolio(state, record) do
    state = apply_raw_item(state, "portfolio", record)

    persist_portfolio(
      state,
      trim_string(record["name"]),
      trim_string(record["base_currency"]),
      trim_string(record["external_id"])
    )
  end

  defp process_securities(state),
    do: reduce_records(state, Map.get(state.preview, "securities", []), &process_security/2)

  defp process_security(state, record) do
    state = apply_raw_item(state, "security", record)

    symbol = trim_string(record["symbol"]) || trim_string(record["ticker"])

    persist_security(
      state,
      trim_string(record["name"]),
      symbol,
      trim_string(record["currency"]),
      trim_string(record["isin"]),
      trim_string(record["external_id"])
    )
  end

  defp process_accounts(state),
    do: reduce_records(state, Map.get(state.preview, "accounts", []), &process_account/2)

  defp process_account(state, record) do
    state = apply_raw_item(state, "account", record)

    persist_account(
      state,
      trim_string(record["name"]),
      trim_string(record["currency"]),
      trim_string(record["type"]),
      trim_string(record["external_id"])
    )
  end

  defp process_taxonomies(state),
    do: reduce_records(state, Map.get(state.preview, "taxonomies", []), &process_taxonomy/2)

  defp process_taxonomy(state, record) do
    state = apply_raw_item(state, "taxonomy", record)

    persist_taxonomy(state, trim_string(record["name"]), trim_string(record["external_id"]))
  end

  defp process_categories(state),
    do: reduce_records(state, Map.get(state.preview, "categories", []), &process_category/2)

  defp process_category(state, record) do
    state = apply_raw_item(state, "category", record)

    persist_category_and_assignment(
      state,
      trim_string(record["name"]),
      trim_string(record["external_id"]),
      trim_string(record["taxonomy_external_id"])
    )
  end

  defp process_transactions(state),
    do: reduce_records(state, Map.get(state.preview, "transactions", []), &process_transaction/2)

  defp process_transaction(state, record) do
    state = apply_raw_item(state, "transaction", record)

    persist_transaction(
      state,
      trim_string(record["external_id"]),
      trim_string(record["type"]),
      trim_string(record["date"]),
      trim_string(record["amount"]),
      trim_string(record["currency"]),
      trim_string(record["account_reference_id"]),
      trim_string(record["security_reference_id"])
    )
  end

  defp reduce_records(state, records, callback) when is_list(records),
    do: Enum.reduce(records, state, fn record, state_acc -> callback.(state_acc, record) end)

  defp reduce_records(state, _records, _callback), do: state

  defp persist_portfolio(state, name, base_currency_code, external_id) do
    with true <- not is_nil(name),
         true <- not is_nil(base_currency_code),
         true <- not is_nil(state.currencies_by_code[base_currency_code]) do
      existing =
        Repo.one(
          from(p in Portfolio,
            where: p.name == ^name and p.base_currency_code == ^base_currency_code,
            order_by: [asc: p.id],
            limit: 1
          )
        )

      case existing do
        %Portfolio{} = portfolio ->
          state
          |> cache_portfolio(portfolio, external_id)
          |> set_primary_portfolio(portfolio)
          |> increment("skipped", "portfolios")

        nil ->
          case Portfolixir.Portfolios.create_portfolio(%{
                 name: name,
                 base_currency_code: base_currency_code
               }) do
            {:ok, portfolio} ->
              state
              |> cache_portfolio(portfolio, external_id)
              |> set_primary_portfolio(portfolio)
              |> increment("created", "portfolios")

            {:error, changeset} ->
              state
              |> increment("failed", "portfolios")
              |> append_warning(
                "Could not create portfolio #{name}: #{inspect(changeset.errors)}"
              )
          end
      end
    else
      _ ->
        state
        |> increment("failed", "portfolios")
        |> append_warning("Skipping invalid portfolio row with name=#{inspect(name)}")
    end
  end

  defp persist_security(state, name, symbol, currency_code, isin, external_id) do
    with true <- not is_nil(name),
         true <- not is_nil(symbol),
         true <- not is_nil(currency_code),
         true <- not is_nil(state.currencies_by_code[currency_code]) do
      existing =
        Repo.one(
          from(s in Security,
            where: s.name == ^name and s.symbol == ^symbol and s.currency_code == ^currency_code,
            order_by: [asc: s.id],
            limit: 1
          )
        )

      case existing do
        %Security{} = security ->
          cache_security(state, security, external_id)
          |> increment("skipped", "securities")

        nil ->
          case Catalog.create_security(%{
                 name: name,
                 symbol: symbol,
                 currency_code: currency_code,
                 isin: isin
               }) do
            {:ok, security} ->
              state
              |> cache_security(security, external_id)
              |> increment("created", "securities")

            {:error, changeset} ->
              state
              |> increment("failed", "securities")
              |> append_warning("Could not create security #{name}: #{inspect(changeset.errors)}")
          end
      end
    else
      _ ->
        state
        |> increment("failed", "securities")
        |> append_warning("Skipping invalid security row with name=#{inspect(name)}")
    end
  end

  defp persist_account(state, name, currency_code, type, external_id) do
    with true <- not is_nil(name),
         true <- type == "cash",
         true <- not is_nil(currency_code),
         %Portfolio{} = portfolio <- state.primary_portfolio do
      existing =
        Repo.one(
          from(a in DepositAccount,
            where:
              a.portfolio_id == ^portfolio.id and a.name == ^name and
                a.currency_code == ^currency_code,
            order_by: [asc: a.id],
            limit: 1
          )
        )

      case existing do
        %DepositAccount{} = account ->
          cache_account(state, account, external_id)
          |> increment("skipped", "accounts")

        nil ->
          case Portfolixir.Portfolios.create_deposit_account(%{
                 portfolio_id: portfolio.id,
                 name: name,
                 currency_code: currency_code
               }) do
            {:ok, account} ->
              cache_account(state, account, external_id)
              |> increment("created", "accounts")

            {:error, changeset} ->
              state
              |> increment("failed", "accounts")
              |> append_warning("Could not create account #{name}: #{inspect(changeset.errors)}")
          end
      end
    else
      nil ->
        state
        |> increment("skipped", "accounts")
        |> append_warning("Skipping account #{inspect(name)}: no portfolio available")

      _ ->
        state
        |> increment("failed", "accounts")
        |> append_warning("Skipping invalid account row with name=#{inspect(name)}")
    end
  end

  defp persist_taxonomy(state, name, external_id) do
    with true <- not is_nil(name) do
      case Taxonomies.get_taxonomy_by_name(name) do
        %Taxonomy{} = taxonomy ->
          cache_taxonomy(state, taxonomy, external_id)
          |> increment("skipped", "taxonomies")

        nil ->
          case Taxonomies.create_taxonomy(%{name: name}) do
            {:ok, taxonomy} ->
              cache_taxonomy(state, taxonomy, external_id)
              |> increment("created", "taxonomies")

            {:error, changeset} ->
              state
              |> increment("failed", "taxonomies")
              |> append_warning("Could not create taxonomy #{name}: #{inspect(changeset.errors)}")
          end
      end
    else
      _ ->
        state
        |> increment("failed", "taxonomies")
        |> append_warning("Skipping invalid taxonomy row with name=#{inspect(name)}")
    end
  end

  defp persist_category_and_assignment(state, name, external_id, taxonomy_external_id) do
    case resolve_taxonomy_id(state, taxonomy_external_id) do
      nil ->
        state
        |> increment("skipped", "categories")
        |> append_warning(
          "Category #{inspect(name)} skipped: missing mapped taxonomy #{inspect(taxonomy_external_id)}"
        )

      taxonomy_id when is_integer(taxonomy_id) ->
        existing =
          Repo.one(
            from(c in Category,
              where: c.taxonomy_id == ^taxonomy_id and c.name == ^name,
              order_by: [asc: c.id],
              limit: 1
            )
          )

        state =
          case existing do
            %Category{} = category ->
              state
              |> cache_category(category, external_id)
              |> increment("skipped", "categories")

            nil ->
              case Taxonomies.create_category(%{taxonomy_id: taxonomy_id, name: name}) do
                {:ok, category} ->
                  state
                  |> cache_category(category, external_id)
                  |> increment("created", "categories")

                {:error, changeset} ->
                  state
                  |> increment("failed", "categories")
                  |> append_warning(
                    "Could not create category #{name}: #{inspect(changeset.errors)}"
                  )

                  state
              end
          end

        assign_first_security_to_cached_category(state, external_id)
    end
  end

  defp assign_first_security_to_cached_category(state, category_external_id) do
    security = state.securities_by_external_id |> Map.values() |> List.first()
    category = state.categories_by_external_id[category_external_id]

    cond do
      is_nil(security) ->
        state

      is_nil(category) ->
        state

      true ->
        case assignment_exists?(security.id, category.id) do
          true ->
            state
            |> increment("skipped", "assignments")
            |> append_warning(
              "Category #{inspect(category.name)} already assigned to security #{inspect(security.name)}"
            )

          false ->
            case Catalog.assign_category_to_security(security.id, category.id) do
              {:ok, _assignment} ->
                increment(state, "created", "assignments")

              {:error, changeset} ->
                state
                |> increment("skipped", "assignments")
                |> append_warning(
                  "Could not assign category #{inspect(category.name)}: #{inspect(changeset.errors)}"
                )
            end
        end
    end
  end

  defp assignment_exists?(security_id, category_id) do
    Repo.exists?(
      from(a in SecurityCategoryAssignment,
        where: a.security_id == ^security_id and a.category_id == ^category_id
      )
    )
  end

  defp resolve_taxonomy_id(state, external_id) do
    case state.taxonomies_by_external_id[external_id] do
      %Taxonomy{} = taxonomy -> taxonomy.id
      _ -> nil
    end
  end

  defp persist_transaction(
         state,
         external_id,
         raw_type,
         raw_date,
         raw_amount,
         currency_code,
         account_reference_id,
         security_reference_id
       ) do
    with true <- not is_nil(external_id),
         true <- not is_nil(raw_type),
         true <- not is_nil(currency_code),
         {:ok, type} <- map_transaction_type(raw_type),
         {:ok, date} <- parse_date(raw_date),
         {:ok, amount} <- parse_amount(raw_amount),
         %Portfolio{} = portfolio <- state.primary_portfolio,
         %DepositAccount{} = account <- state.accounts_by_external_id[account_reference_id] do
      notes = "pp_import:#{external_id}"

      existing =
        Repo.get_by(Ledger.Transaction,
          portfolio_id: portfolio.id,
          notes: notes,
          type: type,
          date: date,
          currency_code: currency_code,
          amount: amount
        )

      if existing do
        increment(state, "skipped", "transactions")
      else
        attrs = %{
          portfolio_id: portfolio.id,
          type: type,
          date: date,
          currency_code: currency_code,
          amount: amount,
          deposit_account_id: account.id,
          notes: notes
        }

        case maybe_add_security_to_transaction(attrs, raw_type, security_reference_id, state) do
          {:ok, final_attrs} ->
            case Ledger.create_transaction(final_attrs) do
              {:ok, _} ->
                increment(state, "created", "transactions")

              {:error, changeset} ->
                state
                |> increment("failed", "transactions")
                |> append_warning(
                  "Could not create transaction #{external_id}: #{inspect(changeset.errors)}"
                )
            end

          {:skip, warning} ->
            state
            |> increment("skipped", "transactions")
            |> append_warning(warning)
        end
      end
    else
      {:error, reason} ->
        state
        |> increment("skipped", "transactions")
        |> append_warning("Skipping transaction #{inspect(external_id)}: #{inspect(reason)}")

      nil ->
        state
        |> increment("skipped", "transactions")
        |> append_warning(
          "Skipping transaction #{inspect(external_id)}: missing portfolio or account"
        )

      _ ->
        state
        |> increment("failed", "transactions")
        |> append_warning("Skipping invalid transaction row #{inspect(external_id)}")
    end
  end

  defp maybe_add_security_to_transaction(attrs, _raw_type, nil, _state),
    do: {:ok, attrs}

  defp maybe_add_security_to_transaction(attrs, _raw_type, security_reference_id, state)
       when is_binary(security_reference_id) do
    case state.securities_by_external_id[security_reference_id] do
      %Security{} = security ->
        {:ok, Map.put(attrs, :security_id, security.id)}

      _ ->
        {:skip,
         "Skipping transaction #{inspect(attrs[:notes])}: missing mapped security #{inspect(security_reference_id)}"}
    end
  end

  defp map_transaction_type("BUY"), do: {:ok, "withdrawal"}
  defp map_transaction_type("buy"), do: {:ok, "withdrawal"}
  defp map_transaction_type("SELL"), do: {:ok, "deposit"}
  defp map_transaction_type("sell"), do: {:ok, "deposit"}
  defp map_transaction_type(other), do: {:error, {:unsupported_transaction_type, other}}

  defp parse_date(nil), do: {:error, :invalid_date}

  defp parse_date(date) do
    Date.from_iso8601(date)
  end

  defp parse_amount(nil), do: {:error, :invalid_amount}

  defp parse_amount(amount) do
    try do
      {:ok, Decimal.new(amount)}
    rescue
      _ -> {:error, :invalid_amount}
    end
  end

  defp apply_raw_item(state, record_type, record) do
    case upsert_raw_item(state, record_type, record) do
      {:ok, _status, updated_state} ->
        updated_state

      {:error, _reason, updated_state} ->
        updated_state
    end
  end

  defp upsert_raw_item(state, record_type, record) do
    external_id = trim_string(Map.get(record, "external_id"))
    content = raw_payload(record_type, external_id, record)
    content_hash = raw_content_hash(content)

    existing =
      case external_id do
        nil ->
          nil

        _ ->
          Repo.get_by(RawImportItem,
            import_source_id: state.import_source.id,
            external_id: external_id
          )
      end

    existing =
      case existing do
        %RawImportItem{} = raw_item ->
          raw_item

        nil ->
          Repo.get_by(RawImportItem,
            import_source_id: state.import_source.id,
            content_hash: content_hash
          )
      end

    case existing do
      %RawImportItem{} ->
        {:ok, :already_exists, state}

      nil ->
        case Imports.create_raw_import_item(%{
               import_source_id: state.import_source.id,
               import_run_id: state.import_run.id,
               external_id: external_id,
               content_hash: content_hash,
               content_type: @raw_content_type,
               payload: content,
               status: "new"
             }) do
          {:ok, _item} ->
            {:ok, :created, increment(state, "created", "raw_items")}

          {:error, changeset} ->
            {:error, changeset,
             state
             |> increment("failed", "raw_items")
             |> append_warning(
               "Could not persist raw item #{record_type} #{inspect(external_id)}: #{inspect(changeset.errors)}"
             )}
        end
    end
  end

  defp raw_payload(record_type, external_id, record) do
    %{
      "source" => @raw_source_name,
      "record_type" => record_type,
      "record_external_id" => external_id,
      "payload" => normalize_payload(record)
    }
  end

  defp normalize_payload(value) when is_struct(value) do
    inspect(value)
  end

  defp normalize_payload(value) when is_map(value) do
    Map.new(value, fn {key, child} ->
      {to_string(key), normalize_payload(child)}
    end)
  end

  defp normalize_payload(value) when is_list(value) do
    Enum.map(value, &normalize_payload/1)
  end

  defp normalize_payload(value) do
    value
  end

  defp raw_content_hash(payload) do
    payload
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> then(&"sha256:#{&1}")
  end

  defp cache_portfolio(state, %Portfolio{} = portfolio, external_id)
       when is_binary(external_id) do
    put_in(state, [:portfolios_by_external_id, external_id], portfolio)
  end

  defp cache_portfolio(state, %Portfolio{}, _external_id), do: state

  defp cache_security(state, %Security{} = security, external_id) when is_binary(external_id) do
    put_in(state, [:securities_by_external_id, external_id], security)
  end

  defp cache_security(state, %Security{}, _external_id), do: state

  defp cache_account(state, %DepositAccount{} = account, external_id)
       when is_binary(external_id) do
    put_in(state, [:accounts_by_external_id, external_id], account)
  end

  defp cache_account(state, %DepositAccount{}, _external_id), do: state

  defp cache_category(state, %Category{} = category, external_id) when is_binary(external_id) do
    put_in(state, [:categories_by_external_id, external_id], category)
  end

  defp cache_category(state, %Category{}, _external_id), do: state

  defp cache_taxonomy(state, %Taxonomy{} = taxonomy, external_id) when is_binary(external_id) do
    put_in(state, [:taxonomies_by_external_id, external_id], taxonomy)
  end

  defp cache_taxonomy(state, %Taxonomy{}, _external_id), do: state

  defp set_primary_portfolio(state, %Portfolio{} = portfolio) do
    if is_nil(state.primary_portfolio), do: %{state | primary_portfolio: portfolio}, else: state
  end

  defp increment(state, section, key) do
    update_in(state, [:summary, section, key], &(&1 + 1))
  end

  defp append_warning(state, warning) do
    update_in(state, [:summary, "warnings"], fn warnings -> warnings ++ [warning] end)
  end

  defp trim_string(nil), do: nil

  defp trim_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> then(fn
      "" -> nil
      cleaned -> cleaned
    end)
  end

  defp trim_string(_), do: nil

  defp utc_now do
    DateTime.utc_now() |> DateTime.truncate(:microsecond)
  end
end
