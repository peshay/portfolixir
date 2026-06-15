defmodule Portfolixir.Journal.Serializer do
  @moduledoc """
  JSONB-safe encoding of `before`/`after` snapshots for the audit journal
  (ADR-0017, FR-28).

  Owns the one type-mapping table for journal payloads. Decimals are encoded as
  **strings** (Jason would emit them as floats and lose precision), and dates as
  ISO-8601 strings. Ecto associations and schema metadata are dropped. Any type
  the table does not cover raises, so a newly added field cannot be silently
  omitted from the audit record.
  """

  @doc """
  Serializes an Ecto schema struct (or plain map) into a JSON-safe map of its
  persisted fields. Association placeholders, `__meta__` and `__struct__` are
  dropped; remaining values go through `encode_value/1`.
  """
  @spec snapshot(struct() | map() | nil) :: map() | nil
  def snapshot(nil), do: nil

  def snapshot(%_{} = struct) do
    struct
    |> persisted_fields()
    |> Map.new(fn {key, value} -> {Atom.to_string(key), encode_value(value)} end)
  end

  def snapshot(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), encode_value(value)} end)
  end

  defp persisted_fields(%schema{} = struct) do
    fields =
      if function_exported?(schema, :__schema__, 1) do
        schema.__schema__(:fields)
      else
        struct |> Map.from_struct() |> Map.keys()
      end

    Enum.flat_map(fields, fn field ->
      case Map.get(struct, field) do
        %Ecto.Association.NotLoaded{} -> []
        value -> [{field, value}]
      end
    end)
  end

  @doc "Encodes one value into a JSON-safe term."
  @spec encode_value(term()) :: term()
  def encode_value(nil), do: nil
  def encode_value(value) when is_binary(value), do: value
  def encode_value(value) when is_boolean(value), do: value
  def encode_value(value) when is_integer(value), do: value
  def encode_value(value) when is_float(value), do: value
  def encode_value(value) when is_atom(value), do: Atom.to_string(value)
  def encode_value(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  def encode_value(%Date{} = value), do: Date.to_iso8601(value)
  def encode_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  def encode_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  def encode_value(%Time{} = value), do: Time.to_iso8601(value)
  def encode_value(value) when is_list(value), do: Enum.map(value, &encode_value/1)

  def encode_value(%Ecto.Association.NotLoaded{}), do: nil

  def encode_value(%_{} = nested), do: snapshot(nested)

  def encode_value(value) when is_map(value) do
    Map.new(value, fn {key, inner} -> {to_string(key), encode_value(inner)} end)
  end

  def encode_value(other) do
    raise ArgumentError,
          "Portfolixir.Journal.Serializer has no mapping for #{inspect(other)}; " <>
            "add it to the type table rather than dropping it from the audit record"
  end
end
