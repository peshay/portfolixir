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
  alias Portfolixir.Ledger.SettlementGuard
  alias Portfolixir.Ledger.Transaction

  @trade_types ["buy", "sell"]
  @fields ["settlement_amount", "settlement_fx_rate", "settlement_source", "settlement_mode"]
  @reprefill_targets ["security_id", "securities_account_id", "date", "type"]

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
  def derive(params, _target, nil),
    do: Map.drop(params, @fields -- ["settlement_mode"])

  def derive(params, target, pair) do
    security_amount = security_amount(params)
    amount = decimal(params["settlement_amount"])
    rate = decimal(params["settlement_fx_rate"])

    cond do
      target == "settlement_amount" ->
        params
        |> Map.put("settlement_source", "entered")
        |> put_rate(amount && positive(security_amount) && Decimal.div(amount, security_amount))

      target == "settlement_fx_rate" ->
        params
        |> Map.put("settlement_source", "entered")
        |> put_amount(rate && security_amount && Decimal.mult(security_amount, rate))

      is_nil(rate) or (target in @reprefill_targets and params["settlement_source"] != "entered") ->
        prefill(params, pair, security_amount)

      true ->
        put_amount(params, security_amount && Decimal.mult(security_amount, rate))
    end
  end

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
    with {:ok, date} <- Date.from_iso8601(to_string(date)),
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
        security_amount = security_amount(params)

        expected =
          SettlementGuard.expected_cash(
            params["type"],
            amount,
            decimal(params["fees"]),
            decimal(params["taxes"])
          )

        {:ok,
         params
         |> Map.drop(@fields)
         |> Map.merge(%{
           "currency_code" => pair.security,
           "security_amount" => security_amount && Decimal.to_string(security_amount, :normal),
           "settlement_amount" => Decimal.to_string(amount, :normal),
           "settlement_fx_rate" => nil,
           "gross_amount" => expected && Decimal.to_string(expected, :normal)
         })}
    end
  end

  @doc """
  The fieldset's values for a stored booking (the edit drawer); a row in the
  importer's account-currency form is marked so it edits as it was booked.
  """
  @spec from_transaction(Transaction.t(), [map()]) :: map()
  def from_transaction(%Transaction{settlement_amount: %Decimal{}} = transaction, securities) do
    case find_by_id(securities, to_string(transaction.security_id)) do
      %{currency_code: currency} when currency != transaction.currency_code ->
        %{"settlement_mode" => "account"}

      _booked_in_the_security_currency ->
        %{
          "settlement_amount" => plain(transaction.settlement_amount),
          "settlement_fx_rate" =>
            transaction.settlement_fx_rate && plain(transaction.settlement_fx_rate),
          "settlement_source" => "entered"
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

  defp positive(%Decimal{} = value), do: Decimal.compare(value, 0) == :gt
  defp positive(_value), do: false

  # The form boundary's German comma (one comma, no dot, means a decimal
  # point) — the same rule the booking form applies to its other amounts.
  defp decimal(value) when is_binary(value) do
    trimmed = String.trim(value)

    normalized =
      if not String.contains?(trimmed, ".") and length(String.split(trimmed, ",")) == 2,
        do: String.replace(trimmed, ",", "."),
        else: trimmed

    case Decimal.parse(normalized) do
      {decimal, ""} -> decimal
      _invalid -> nil
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
