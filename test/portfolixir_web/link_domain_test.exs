defmodule PortfolixirWeb.LinkDomainTest do
  # Sprint 29, N3/N4 (ADR-0056 E2), closing act F2: a link's domain as a
  # screen shows it must be the host the browser opens. Elixir's
  # `URI.parse/1` reads RFC 3986, a browser the WHATWG URL standard, and
  # the two disagree on a backslash: a browser reads `\` in an http(s)
  # link's authority as `/`, so `https://attacker.example\@ir.example/`
  # opens `attacker.example` where RFC 3986 reads the host `ir.example`.
  # Synthetic hosts only.
  use ExUnit.Case, async: true

  alias PortfolixirWeb.LinkDomain

  # User story (closing act, F2):
  # As the operator reading an entry's or a story's source,
  # I want the domain shown to be the one the link opens,
  # so that a crafted link cannot show a trusted domain and open another.
  #
  # Acceptance criteria:
  # - A link with a backslash in its authority (between `//` and the first
  #   `/`, `?` or `#`) reads „link“, never a host.
  # - A backslash after the authority leaves the host shown.
  test "a backslash in the authority reads „link“, not a host" do
    for url <- [
          "https://attacker.example\\@ir.example/report",
          "https://attacker.example\\ir.example/report",
          "https://ir.example\\",
          "http://user\\@ir.example?q=1"
        ] do
      assert LinkDomain.of(url) == "link", url
    end

    assert LinkDomain.of("https://IR.Example/a\\b") == "ir.example"
    assert LinkDomain.of("https://ir.example/report?x=a\\@b.example") == "ir.example"
    assert LinkDomain.of("https://ir.example/report") == "ir.example"
  end
end
