defmodule PortfolixirWeb.Transactions.SettlementForm do
  @moduledoc """
  The booking form's cross-currency settlement (#395 rescoped, pick F3-A of
  board `ux-design-2026-09-23/03-settlement-inputs`; ADR-0015).

  A buy or sell of a security whose currency differs from the depot's cash
  account is a cross-currency settlement: booked in the security's currency,
  its cash leg in the account's. Before this module the form stamped the
  account currency on every booking, so a USD price was saved as euros. Now a
  fieldset asks for the settlement exactly when the two currencies differ:

    * the **settlement amount** in the account currency and the **rate**
      (account units per one security unit) derive each other as either is
      typed; a changed quantity or price re-derives the amount from the rate;
    * both are prefilled from the stored exchange rates on or before the
      booking date and say so — a suggestion, the broker statement wins;
    * on save the booking carries `security_amount = quantity × price`, the
      settlement amount, and a cash amount computed by the settlement guard's
      own arithmetic (`Ledger.SettlementGuard.expected_cash/4`: plus fees and
      taxes on a buy, less them on a sell), so the form cannot produce a
      booking the guard refuses. The rate itself is not sent: the ledger
      derives it from the two amounts (the broker's actual rate, ADR-0015).

  Fees and taxes are in the account currency, the currency of the cash leg
  they are part of.

  **The importer's form is left alone.** The Portfolio Performance importer
  books a cross-currency trade in the *account's* currency (price in EUR, the
  two settlement legs stored beside it). Editing such a row keeps that form:
  it opens with `settlement_mode = "account"`, which suppresses the fieldset,
  and a save sends none of the settlement fields, so its figures are never
  re-read as a booking in the security's currency.
  """

  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Fx
  alias Portfolixir.Input.BoundedDate
  alias Portfolixir.Input.BoundedDecimal
  alias Portfolixir.Ledger.SettlementGuard
  alias Portfolixir.Ledger.Transaction

  @trade_types ["buy", "sell"]
  @fields ["settlement_amount", "settlement_fx_rate", "settlement_source", "settlement_mode"]
  @reprefill_targets ["security_id", "securities_account_id", "date", "type"]
  @trade_fields ["quantity", "price"]
  @typed_sources ["amount", "rate"]

  @doc """
  The two currencies when the form describes a cross-currency trade, else nil.
  """
  @spec pair(map(), [map()], [map()]) :: %{security: String.t(), account: String.t()} | nil
  def pair(%{"settlement_mode" => "account"}, _securities_accounts, _securities), do: nil

  def pair(params, securities_accounts, securities) do
    with true <- params["type"] in @trade_types,
         %{cash_account: %{currency_code: account}} <-
           find_by_id(securities_accounts, params["securities_account_id"]),
         %{currency_code: security} when is_binary(security) and security != account <-
           find_by_id(securities, params["security_id"]) do
      %{security: security, account: account}
    else
      _same_currency_or_incomplete -> nil
    end
  end

  defp find_by_id(list, id) when is_binary(id) and id != "",
    do: Enum.find(list, &(to_string(&1.id) == id))

  defp find_by_id(_list, _id), do: nil

  @doc """
  The form's derivation on a change event. `target` is the field the
  operator just edited (the event's `_target`).
  """
  @spec derive(map(), String.t() | nil, map() | nil) :: map()
  def derive(%{"settlement_mode" => "account"} = params, _target, nil), do: params

  def derive(params, _target, nil),
    do: Map.drop(params, @fields -- ["settlement_mode"])

  # The figure the operator typed last is authoritative (closing act, both
  # hunters: a note or a fee used to re-derive the amount from the rounded
  # rate, moving the broker's figure by a cent). A typed amount survives a
  # changed quantity or price — the rate follows it; a typed rate makes the
  # amount follow it; nothing else re-derives a typed figure. Only a
  # suggestion (the stored rate) is refreshed when the pair or date changes.
  def derive(params, target, pair) do
    security_amount = security_amount(params)
    amount = decimal(params["settlement_amount"])
    rate = decimal(params["settlement_fx_rate"])
    typed = params["settlement_source"] in @typed_sources

    cond do
      target == "settlement_amount" ->
        params
        |> Map.put("settlement_source", "amount")
        |> put_rate(ratio(amount, security_amount))

      target == "settlement_fx_rate" ->
        params
        |> Map.put("settlement_source", "rate")
        |> put_amount(product(security_amount, rate))

      typed and target in @trade_fields ->
        follow_typed(params, security_amount, amount, rate)

      typed ->
        params

      is_nil(rate) or target in @reprefill_targets ->
        prefill(params, pair, security_amount)

      target in @trade_fields ->
        put_amount(params, product(security_amount, rate))

      true ->
        params
    end
  end

  defp follow_typed(%{"settlement_source" => "amount"} = params, security_amount, amount, _rate),
    do: put_rate(params, ratio(amount, security_amount))

  defp follow_typed(params, security_amount, _amount, rate),
    do: put_amount(params, product(security_amount, rate))

  defp ratio(%Decimal{} = amount, %Decimal{} = security_amount) do
    if Decimal.compare(security_amount, 0) == :gt, do: Decimal.div(amount, security_amount)
  end

  defp ratio(_amount, _security_amount), do: nil

  defp product(%Decimal{} = security_amount, %Decimal{} = rate),
    do: Decimal.mult(security_amount, rate)

  defp product(_security_amount, _rate), do: nil

  defp prefill(params, pair, security_amount) do
    case stored_rate(pair, params["date"]) do
      {:ok, rate} ->
        rate = Decimal.round(rate, 6)

        params
        |> Map.put("settlement_source", "stored")
        |> put_rate(rate)
        |> put_amount(security_amount && Decimal.mult(security_amount, rate))

      :error ->
        params
        |> Map.put("settlement_source", "none")
        |> Map.put("settlement_fx_rate", "")
        |> Map.put("settlement_amount", "")
    end
  end

  defp stored_rate(pair, date) do
    with {:ok, date} <- BoundedDate.parse(date),
         {:ok, rate} <- Fx.rate(pair.security, pair.account, date) do
      {:ok, rate}
    else
      _no_date_or_rate -> :error
    end
  end

  defp put_rate(params, nil), do: params

  defp put_rate(params, rate),
    do: Map.put(params, "settlement_fx_rate", rate |> Decimal.round(6) |> plain())

  defp put_amount(params, nil), do: params

  defp put_amount(params, amount),
    do:
      Map.put(
        params,
        "settlement_amount",
        amount |> Decimal.round(2) |> Decimal.to_string(:normal)
      )

  @doc """
  The params the ledger receives on save. `{:error, errors}` when a
  cross-currency trade has no settlement amount — named on the field rather
  than left to the ledger's rate error, which names a field the form does not
  show.
  """
  @spec prepare(map(), map() | nil) :: {:ok, map()} | {:error, %{String.t() => String.t()}}
  # The importer's account-currency form (closing act, edge-case hunter): its
  # cash amount follows its stored settlement, so a corrected fee or type
  # keeps the guard's relation; the settlement itself is not re-sent.
  def prepare(%{"settlement_mode" => "account"} = params, nil) do
    expected =
      case decimal(params["settlement_amount"]) do
        %Decimal{} = settlement -> cash_for(params, settlement)
        nil -> nil
      end

    params = Map.drop(params, @fields)

    {:ok, if(expected, do: Map.put(params, "gross_amount", plain_string(expected)), else: params)}
  end

  # Leaving the pair (an edit to a security in the account's currency): the
  # legs and the cash amount they implied go, or the booking keeps a cash
  # amount its new figures do not produce (closing act, edge-case hunter).
  def prepare(%{"settlement_mode" => "security"} = params, nil) do
    {:ok,
     params
     |> Map.drop(@fields)
     |> Map.merge(%{
       "security_amount" => nil,
       "settlement_amount" => nil,
       "settlement_fx_rate" => nil,
       "gross_amount" => nil
     })}
  end

  def prepare(params, nil), do: {:ok, Map.drop(params, @fields)}

  def prepare(params, pair) do
    case decimal(params["settlement_amount"]) do
      nil ->
        {:error,
         %{
           "settlement_amount" =>
             gettext("is required when the security and the cash account differ in currency")
         }}

      amount ->
        prepare_settled(params, pair, amount)
    end
  end

  defp prepare_settled(params, pair, amount) do
    security_amount = security_amount(params)
    expected = cash_for(params, amount)

    if expected && Decimal.negative?(expected) do
      {:error, %{"settlement_amount" => gettext("is less than the fees and taxes of this sale")}}
    else
      {:ok,
       params
       |> Map.drop(@fields)
       |> Map.merge(%{
         "currency_code" => pair.security,
         "security_amount" => security_amount && plain_string(security_amount),
         "settlement_amount" => plain_string(amount),
         # The ledger derives the rate from the two amounts (the broker's
         # actual rate, ADR-0015); a trade worth nothing has no amounts to
         # derive it from, so the form's rate is recorded instead.
         "settlement_fx_rate" => zero_trade_rate(security_amount, params),
         "gross_amount" => cash_string(expected)
       })}
    end
  end

  defp cash_for(params, settlement) do
    SettlementGuard.expected_cash(
      params["type"],
      settlement,
      decimal(params["fees"]),
      decimal(params["taxes"])
    )
  end

  # No cash moves on a trade worth nothing: no cash amount is recorded.
  defp cash_string(%Decimal{} = expected) do
    if Decimal.eq?(expected, 0), do: nil, else: plain_string(expected)
  end

  defp cash_string(nil), do: nil

  defp zero_trade_rate(%Decimal{} = security_amount, params) do
    with true <- Decimal.eq?(security_amount, 0),
         %Decimal{} = rate <- decimal(params["settlement_fx_rate"]) do
      plain_string(rate)
    else
      _derived_by_the_ledger -> nil
    end
  end

  defp zero_trade_rate(_security_amount, _params), do: nil

  defp plain_string(decimal), do: Decimal.to_string(decimal, :normal)

  @doc """
  The fieldset's values for a stored booking (the edit drawer); a row in the
  importer's account-currency form is marked so it edits as it was booked.
  """
  @spec from_transaction(%Transaction{}, [map()]) :: map()
  def from_transaction(%Transaction{settlement_amount: %Decimal{}} = transaction, securities) do
    case find_by_id(securities, to_string(transaction.security_id)) do
      %{currency_code: currency} when currency != transaction.currency_code ->
        %{
          "settlement_mode" => "account",
          "settlement_amount" => plain(transaction.settlement_amount)
        }

      _booked_in_the_security_currency ->
        %{
          "settlement_mode" => "security",
          "settlement_amount" => plain(transaction.settlement_amount),
          "settlement_fx_rate" =>
            transaction.settlement_fx_rate && plain(transaction.settlement_fx_rate),
          "settlement_source" => "amount"
        }
    end
  end

  def from_transaction(%Transaction{}, _securities), do: %{}

  defp security_amount(params) do
    with %Decimal{} = quantity <- decimal(params["quantity"]),
         %Decimal{} = price <- decimal(params["price"]) do
      Decimal.mult(quantity, price)
    end
  end

  # The form boundary's German comma (one comma, no dot, means a decimal
  # point) — the same rule the booking form applies to its other amounts.
  defp decimal(value) when is_binary(value) do
    trimmed = String.trim(value)

    normalized =
      if not String.contains?(trimmed, ".") and length(String.split(trimmed, ",")) == 2,
        do: String.replace(trimmed, ",", "."),
        else: trimmed

    # Finite only (E25 S4, F17): `NaN` or `Infinity` is no amount or rate.
    case BoundedDecimal.parse(normalized) do
      {:ok, decimal} -> decimal
      :error -> nil
    end
  end

  defp decimal(_value), do: nil

  defp plain(decimal), do: decimal |> Decimal.normalize() |> Decimal.to_string(:normal)

  # The ISO date in running text must not break at its hyphens in the narrow
  # drawer; a non-breaking hyphen (U+2011) keeps it one word.
  defp unbroken_date(date), do: date |> to_string() |> String.replace("-", "\u2011")

  attr(:pair, :map, required: true)
  attr(:form, :map, required: true)
  attr(:errors, :map, required: true)

  @doc """
  The fieldset (board 03, variant A): shown when the currencies differ, the
  two linked inputs, where the suggestion came from, and the guard in one
  sentence so its 422 never surprises.
  """
  def fieldset(assigns) do
    ~H"""
    <fieldset id="settlement-fieldset" class="settlement-fieldset">
      <legend>
        <%= gettext("Settlement in %{account}", account: @pair.account) %>
        <span class="settlement-fieldset__pair">
          · <%= gettext("security in %{security}, account in %{account}",
            security: @pair.security,
            account: @pair.account
          ) %>
        </span>
      </legend>
      <input type="hidden" name="transaction[settlement_source]" value={@form["settlement_source"]} />
      <div class="form-grid">
        <label>
          <span><%= gettext("Settlement amount (%{account})", account: @pair.account) %></span>
          <input
            name="transaction[settlement_amount]"
            value={@form["settlement_amount"]}
            inputmode="decimal"
            aria-invalid={@errors["settlement_amount"] && "true"}
            aria-describedby={
              if @errors["settlement_amount"],
                do: "tx-error-settlement_amount settlement-help",
                else: "settlement-help"
            }
          />
          <p
            :if={@errors["settlement_amount"]}
            id="tx-error-settlement_amount"
            class="field-error"
            role="alert"
          >
            <%= @errors["settlement_amount"] %>
          </p>
        </label>
        <label>
          <span>
            <%= gettext("Rate %{account} per %{security}",
              account: @pair.account,
              security: @pair.security
            ) %>
          </span>
          <input
            name="transaction[settlement_fx_rate]"
            value={@form["settlement_fx_rate"]}
            inputmode="decimal"
            aria-describedby="settlement-help"
          />
        </label>
      </div>
      <p id="settlement-help" class="form-help" data-role="settlement-help">
        <%= case @form["settlement_source"] do %>
          <% "stored" -> %>
            <%= gettext("Rate suggested from the stored exchange rates on or before %{date}.",
              date: unbroken_date(@form["date"])
            ) %>
          <% "none" -> %>
            <%= gettext(
              "No stored exchange rate on or before %{date} — enter the settlement amount from the broker statement.",
              date: unbroken_date(@form["date"])
            ) %>
          <% _entered -> %>
        <% end %>
        <%= gettext(
          "The cash amount is the settlement amount plus fees and taxes on a buy, less them on a sale; fees and taxes are in %{account}.",
          account: @pair.account
        ) %>
      </p>
    </fieldset>
    """
  end
end
