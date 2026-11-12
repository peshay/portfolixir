defmodule PortfolixirWeb.LinkDomain do
  @moduledoc """
  A stored link as a screen shows it: its host, lower-cased, never the link
  in full (ADR-0056 E2). The anchor around it opens the full link.

  Sprint 29 N3 drew it on a research entry's source link; N4 moved it here
  so the story's „To the research log“ form shows its source the same way.
  A link without a host reads „link“.

  **So does a link with a backslash in its authority** (the text between
  `//` and the first `/`, `?` or `#`; closing act of Sprint 29, F2):
  `URI.parse/1` reads RFC 3986, a browser the WHATWG URL standard, which
  reads `\\` in an http(s) link as `/`. `https://attacker.example\\@ir.example/`
  is the host `ir.example` to the one and `attacker.example` to the other,
  so no host is named. The writers refuse such a link now; a row stored
  before stays (ADR-0044), so the screen handles it.
  """
  use Gettext, backend: PortfolixirWeb.Gettext

  @spec of(String.t()) :: String.t()
  def of(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) and host != "" ->
        if backslash_in_authority?(url), do: gettext("link"), else: String.downcase(host)

      _no_host ->
        gettext("link")
    end
  end

  defp backslash_in_authority?(url) do
    case String.split(url, "//", parts: 2) do
      [_scheme, rest] ->
        rest |> String.split(["/", "?", "#"], parts: 2) |> hd() |> String.contains?("\\")

      [_no_authority] ->
        false
    end
  end
end
