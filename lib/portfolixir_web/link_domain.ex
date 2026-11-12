defmodule PortfolixirWeb.LinkDomain do
  @moduledoc """
  A stored link as a screen shows it: its host, lower-cased, never the link
  in full (ADR-0056 E2). The anchor around it opens the full link.

  Sprint 29 N3 drew it on a research entry's source link; N4 moved it here
  so the story's „To the research log“ form shows its source the same way.
  A link without a host reads „link“.
  """
  use Gettext, backend: PortfolixirWeb.Gettext

  @spec of(String.t()) :: String.t()
  def of(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) and host != "" -> String.downcase(host)
      _no_host -> gettext("link")
    end
  end
end
