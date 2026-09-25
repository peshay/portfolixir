defmodule Portfolixir.Input.Text do
  @moduledoc """
  The one rule for text a writer stores (E25 S4, G24 and G17).

  PostgreSQL refuses a NUL character in any text value and a varchar value
  longer than its column, counted in **code points**; Ecto's default length
  count is graphemes, so a name made of combining marks passed the changeset
  and failed in the database. A refusal there is a server error, not a field
  error. This module refuses the same values first, with a field error:

    * invalid UTF-8;
    * NUL and every other C0 control character, DEL and the C1 controls —
      except tab, line feed and carriage return in text that is multi-line by
      nature (`multiline: true`: notes, descriptions);
    * a value longer than `max:` code points, when given.

  `validate/3` is the changeset form every schema uses; `check/2` returns the
  same verdict for a value outside a changeset, so the import parsers name the
  row that carries it before anything is written.
  """

  import Ecto.Changeset

  # C0 minus tab, line feed and carriage return; DEL; C1.
  @multiline_controls ~r/[\x{0}-\x{8}\x{B}\x{C}\x{E}-\x{1F}\x{7F}-\x{9F}]/u
  @single_line_controls ~r/[\x{0}-\x{1F}\x{7F}-\x{9F}]/u

  @type opts :: [max: pos_integer(), multiline: boolean()]
  @type refusal :: :invalid_encoding | :control_characters | :too_long

  @doc """
  The verdict on one value: `:ok` or the first refusal. `nil` is `:ok`.
  """
  @spec check(term(), opts()) :: :ok | {:error, refusal()}
  def check(nil, _opts), do: :ok

  def check(value, opts) when is_binary(value) do
    cond do
      not String.valid?(value) -> {:error, :invalid_encoding}
      Regex.match?(controls(opts), value) -> {:error, :control_characters}
      too_long?(value, opts[:max]) -> {:error, :too_long}
      true -> :ok
    end
  end

  def check(_value, _opts), do: :ok

  @doc "The field error message for a refusal."
  @spec message(refusal(), opts()) :: {String.t(), keyword()}
  def message(:invalid_encoding, _opts),
    do: {"must be valid UTF-8 text", validation: :text}

  def message(:control_characters, opts) do
    if opts[:multiline],
      do:
        {"must not contain control characters other than tabs and line breaks", validation: :text},
      else: {"must not contain control characters or line breaks", validation: :text}
  end

  def message(:too_long, opts),
    do:
      {"should be at most %{count} character(s)",
       count: opts[:max], validation: :length, kind: :max, type: :string}

  @doc """
  Adds the rule to a changeset for each of `fields` (one atom or a list).
  Options: `max:` (code points) and `multiline:` (default `false`).
  """
  @spec validate(Ecto.Changeset.t(), atom() | [atom()], opts()) :: Ecto.Changeset.t()
  def validate(changeset, fields, opts \\ [])

  def validate(changeset, fields, opts) when is_list(fields) do
    Enum.reduce(fields, changeset, &validate(&2, &1, opts))
  end

  def validate(changeset, field, opts) when is_atom(field) do
    validate_change(changeset, field, fn ^field, value ->
      case check(value, opts) do
        :ok ->
          []

        {:error, refusal} ->
          {message, keys} = message(refusal, opts)
          [{field, {message, keys}}]
      end
    end)
  end

  defp controls(opts) do
    if opts[:multiline], do: @multiline_controls, else: @single_line_controls
  end

  defp too_long?(_value, nil), do: false
  defp too_long?(value, max), do: length(String.codepoints(value)) > max
end
