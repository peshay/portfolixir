defmodule PortfolixirWeb.Api.V1.DecimalStringGuard do
  @moduledoc """
  Refuses a JSON number in a financial field of a write before any
  controller sees it (ADR-0003, amendment of 2026-11-01; #1291).

  The JSON decoder turns a number into a binary float, and Ecto's decimal
  cast then stores that float's shortest representation: a value past about
  17 significant digits (`1234567890.12345678`) is stored as a different
  number than the one sent. So every write under `/api/v1` (`POST`, `PUT`,
  `PATCH`, `DELETE`) answers **422** naming the field, with the message
  `"must be a decimal string"`, when a money, quantity, price, fee, tax or
  exchange-rate field carries a JSON number, a float or an integer alike. A
  decimal string reaches the controller unchanged; a JSON `null` is not a
  number and keeps the answer it had. Reads are not inspected.

  The body is read at any depth (a wrapper object such as
  `{"transaction": {...}}`, a list of rows such as a quote batch's
  `quotes`), and a list under a financial key (`church_tax_rates`) is
  refused when any of its items is a number. Every offending field is named,
  each once. Like `PortfolixirWeb.Api.V1.IdRangeGuard`, the guard sits in the
  pipeline rather than in each controller, so a write added later is covered
  without anyone remembering to call it, and a key matched by its suffix
  (`_amount`, `_price`, `_rate`, `_rates`, `_withheld`) is covered when its
  field is added.

  Not read: a security's free-form `attributes` map (operator-defined keys
  whose values are not cast to decimals). Fields outside the six families
  (a target weight, a policy rule's threshold, a split ratio's integer
  terms, a tax year) are not financial amounts in ADR-0003's sense and keep
  their own validation.
  """
  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @message "must be a decimal string"
  @write_methods ~w(POST PUT PATCH DELETE)

  # The financial fields the writes accept today, by family. Kept explicit
  # so the list reads as the contract; the suffixes below cover the rest.
  @money ~w(amount gross_amount security_amount settlement_amount face_value
            amount_granted saver_allowance_single saver_allowance_joint
            taxable_income allowance_granted allowance_used loss_pot_equities
            loss_pot_other loss_carryforward_prior_years withholding_tax_pot
            withholding_tax_credited)
  @quantity ~w(quantity)
  @price ~w(price close)
  @fee ~w(fees fee)
  @tax ~w(taxes tax capital_gains_tax_rate solidarity_surcharge_rate church_tax_rate
          church_tax_rates capital_gains_tax_withheld solidarity_surcharge_withheld
          church_tax_withheld)
  @rate ~w(rate settlement_fx_rate coupon_rate)

  @keys MapSet.new(@money ++ @quantity ++ @price ++ @fee ++ @tax ++ @rate)
  @suffixes ~w(_amount _price _rate _rates _withheld)
  @opaque_subtrees ~w(attributes)

  @doc "The 422 message a refused field carries."
  @spec message() :: String.t()
  def message, do: @message

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: method, body_params: %{} = body} = conn, _opts)
      when method in @write_methods do
    case number_keys(body) do
      [] ->
        conn

      keys ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: Map.new(keys, &{&1, [@message]})})
        |> halt()
    end
  end

  def call(conn, _opts), do: conn

  @doc """
  The financial keys of a params map that carry a JSON number, at any depth,
  in the order first met and each once.
  """
  @spec number_keys(term()) :: [String.t()]
  def number_keys(params), do: params |> collect([]) |> Enum.reverse() |> Enum.uniq()

  defp collect(%{} = map, acc) when not is_struct(map) do
    Enum.reduce(map, acc, fn {key, value}, acc -> check(to_string(key), value, acc) end)
  end

  defp collect(list, acc) when is_list(list), do: Enum.reduce(list, acc, &collect/2)
  defp collect(_other, acc), do: acc

  defp check(key, _value, acc) when key in @opaque_subtrees, do: acc

  defp check(key, value, acc) do
    if financial_key?(key) and number_in?(value), do: [key | acc], else: collect(value, acc)
  end

  defp number_in?(value) when is_number(value), do: true
  defp number_in?(list) when is_list(list), do: Enum.any?(list, &is_number/1)
  defp number_in?(_value), do: false

  defp financial_key?(key),
    do: MapSet.member?(@keys, key) or String.ends_with?(key, @suffixes)
end
