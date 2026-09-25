defmodule Portfolixir.Input.BoundedDate do
  @moduledoc """
  The one rule for a date a writer stores (E25 S4, F70).

  A date is accepted only as an ISO 8601 calendar date string (`YYYY-MM-DD`)
  or a `Date`, and only inside one fixed range of years, `earliest/0` to
  `latest/0`. Ecto's own `:date` cast builds a date from a map of parts or a
  date-time as well, and puts no bound on the year; a year the database
  cannot hold faithfully would reach storage altered, so the stored row, the
  answer and the journal entry would disagree. Inside the range, the date a
  writer validated is the date stored, returned and journaled.

  Two entry points, one rule:

    * `validate/2` for a changeset, applied to every cast date field of every
      schema, so the API, the MCP companion (through the API), the LiveViews,
      the importer and the seeds all meet it;
    * `parse/1` for a date that reaches a write without a cast (a retirement
      date, a split's effective date).

  The lower bound is the importer's existing floor for a plausible booking;
  the upper bound leaves every realistic future date (a scheduled rule, an
  expected event, a time stop) inside the range.
  """

  import Ecto.Changeset

  @earliest ~D[1900-01-01]
  @latest ~D[2999-12-31]
  @iso_date ~r/\A\d{4}-\d{2}-\d{2}\z/

  @doc "The first date a writer may store."
  @spec earliest() :: Date.t()
  def earliest, do: @earliest

  @doc "The last date a writer may store."
  @spec latest() :: Date.t()
  def latest, do: @latest

  @doc "The field error a refused date carries."
  @spec message() :: String.t()
  def message,
    do: "must be a date between #{Date.to_iso8601(@earliest)} and #{Date.to_iso8601(@latest)}"

  @doc "Whether `date` is an ISO calendar `Date` inside the range."
  @spec within?(term()) :: boolean()
  def within?(%Date{calendar: Calendar.ISO} = date) do
    Date.compare(date, @earliest) != :lt and Date.compare(date, @latest) != :gt
  end

  def within?(_other), do: false

  @doc """
  Parses a date that reaches a write without a changeset cast: a `Date` or an
  ISO 8601 `YYYY-MM-DD` string inside the range is `{:ok, date}`; anything
  else is `:error`.
  """
  @spec parse(term()) :: {:ok, Date.t()} | :error
  def parse(%Date{} = date), do: if(within?(date), do: {:ok, date}, else: :error)

  def parse(value) when is_binary(value) do
    with true <- Regex.match?(@iso_date, value),
         {:ok, date} <- Date.from_iso8601(value),
         true <- within?(date) do
      {:ok, date}
    else
      _refused -> :error
    end
  end

  def parse(_value), do: :error

  @doc """
  Refuses a change of each of `fields` that is outside the range, or that was
  given in any form other than an ISO date string or a `Date` (a map of parts,
  a date-time, a basic-format string). A field without a change, or whose cast
  already failed, is left alone; a blank value is `validate_required/3`'s.
  """
  @spec validate(Ecto.Changeset.t(), [atom()]) :: Ecto.Changeset.t()
  def validate(%Ecto.Changeset{} = changeset, fields) when is_list(fields) do
    Enum.reduce(fields, changeset, &validate_field(&2, &1))
  end

  defp validate_field(changeset, field) do
    case fetch_change(changeset, field) do
      {:ok, %Date{} = date} ->
        if within?(date) and given_as_date?(changeset, field),
          do: changeset,
          else: add_error(changeset, field, message(), validation: :bounded_date)

      _no_change_or_blank ->
        changeset
    end
  end

  # The raw value the caller sent, when it came through `cast/4`: a change put
  # by the context itself has no raw form and is judged by its range alone.
  defp given_as_date?(%Ecto.Changeset{params: params}, field) when is_map(params) do
    case Map.fetch(params, Atom.to_string(field)) do
      {:ok, %Date{}} -> true
      {:ok, value} when is_binary(value) -> Regex.match?(@iso_date, value)
      {:ok, _other_form} -> false
      :error -> true
    end
  end

  defp given_as_date?(_changeset, _field), do: true
end
