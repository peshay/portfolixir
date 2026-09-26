defmodule Portfolixir.Net.PathSegment do
  @moduledoc """
  The one way a stored or provider-supplied identifier becomes a segment of an
  outbound request path (E25 S3, F31).

  Percent-encoding with `URI.char_unreserved?/1` turns reserved characters
  (`/`, `?`, `#`, `%`, spaces) into escapes, so a value can neither add a
  segment nor reach the query. The dot, though, is unreserved: a value made
  only of dots would survive encoding as a relative-path segment, and a
  server normalising the path would move the request elsewhere on its host.
  Such a value, and the empty value, is refused here rather than re-encoded
  (servers decode `%2E` back to a dot before normalising), and every adapter
  that places an identifier in a path makes no request for it.
  """

  @doc """
  `{:ok, segment}` for a value that is exactly one path segment once encoded,
  or `{:error, :invalid_path_segment}` for an empty, dot-only or non-string
  value.
  """
  @spec encode(term()) :: {:ok, String.t()} | {:error, :invalid_path_segment}
  def encode(value) when is_binary(value) do
    if relative?(value) do
      {:error, :invalid_path_segment}
    else
      {:ok, URI.encode(value, &URI.char_unreserved?/1)}
    end
  end

  def encode(_value), do: {:error, :invalid_path_segment}

  @doc "Whether a value is empty or made only of dots — a relative-path segment."
  @spec relative?(String.t()) :: boolean()
  def relative?(value) when is_binary(value), do: String.trim(value, ".") == ""
end
