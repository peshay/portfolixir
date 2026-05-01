defmodule Portfolixir.Catalog.FactsheetDocumentTextExtractor do
  @moduledoc "Behaviour and built-in extractor for factsheet text extraction."

  @callback extract_text(binary_content :: binary()) ::
              {:ok, String.t()}
              | {:error, :empty}
              | {:error, :unsupported}
              | {:error, term()}

  @doc "Extract printable text from a synthetic fixture-like PDF payload."
  @spec extract_text(binary()) :: {:ok, String.t()} | {:error, term()}
  def extract_text(_binary_content), do: {:error, :unsupported}
end

defmodule Portfolixir.Catalog.DefaultFactsheetDocumentTextExtractor do
  @moduledoc "Default deterministic extractor used for development and tests."

  @behaviour Portfolixir.Catalog.FactsheetDocumentTextExtractor

  @marker "FACTSHEET_TEXT:"

  @impl true
  def extract_text(binary_content) when is_binary(binary_content) do
    case :binary.match(binary_content, @marker) do
      :nomatch ->
        {:error, :unsupported}

      {index, _} ->
        marker_size = byte_size(@marker)

        _extracted =
          binary_part(
            binary_content,
            index + marker_size,
            byte_size(binary_content) - index - marker_size
          )

        text =
          binary_content
          |> binary_part(index + marker_size, byte_size(binary_content) - index - marker_size)
          |> to_string()
          |> String.trim()
          |> String.replace(~r/\s*EOF\z/, "")
          |> String.trim()

        if text == "" do
          {:error, :empty}
        else
          {:ok, text}
        end
    end
  end

  def extract_text(_), do: {:error, :unsupported}
end
