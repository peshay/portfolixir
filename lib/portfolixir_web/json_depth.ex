defmodule PortfolixirWeb.JsonDepth do
  @moduledoc """
  A nesting bound checked before a JSON text is decoded (security review
  2026-10-12, H02): a deeply nested document costs the decoder time and
  memory far beyond its size, and both the API's body parser and the
  LiveView socket decode before any credential is checked.

  The bound is 100 levels of arrays and objects. The deepest documented
  API body, a security's free-form `attributes` inside its envelope, needs a
  handful; a LiveView message needs fewer than ten. The check is one pass
  over the bytes that skips string contents, so a bracket inside a string
  never counts.
  """

  @max_depth 100

  defmodule TooDeepError do
    @moduledoc "Raised for a JSON text nested past `PortfolixirWeb.JsonDepth.max_depth/0`."
    defexception message: "JSON nested deeper than the server's bound"
  end

  @doc "The deepest nesting of arrays and objects a JSON text may carry."
  @spec max_depth() :: pos_integer()
  def max_depth, do: @max_depth

  @doc """
  Decodes `json` with the endpoint's JSON library once its nesting is within
  the bound; raises `TooDeepError` without decoding otherwise. The body
  parser's `:json_decoder`: Plug.Parsers answers the raise with 400.
  """
  @spec decode!(binary()) :: term()
  def decode!(json) when is_binary(json) do
    if within_bound?(json), do: Phoenix.json_library().decode!(json), else: raise(TooDeepError)
  end

  @doc """
  Whether `json` nests arrays and objects no deeper than the bound. A text
  that is not JSON at all may pass; the decoder refuses it.
  """
  @spec within_bound?(binary()) :: boolean()
  def within_bound?(json) when is_binary(json), do: scan(json, 0)

  defp scan(<<c, rest::binary>>, depth) when c in [?[, ?{] do
    if depth == @max_depth, do: false, else: scan(rest, depth + 1)
  end

  defp scan(<<c, rest::binary>>, depth) when c in [?], ?}], do: scan(rest, depth - 1)
  defp scan(<<?", rest::binary>>, depth), do: skip_string(rest, depth)
  defp scan(<<_c, rest::binary>>, depth), do: scan(rest, depth)
  defp scan(<<>>, _depth), do: true

  defp skip_string(<<?\\, _escaped, rest::binary>>, depth), do: skip_string(rest, depth)
  defp skip_string(<<?", rest::binary>>, depth), do: scan(rest, depth)
  defp skip_string(<<_c, rest::binary>>, depth), do: skip_string(rest, depth)
  defp skip_string(<<>>, _depth), do: true
end
