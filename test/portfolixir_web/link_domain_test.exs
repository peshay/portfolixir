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

  # User story (the Shell polish list #1357, Sprint 29 closing act #1458;
  # Sprint 30 plan, F2):
  # As the maintainer reading LinkDomain,
  # I want no branch that never runs,
  # so that the backslash check reads as what it guards.
  #
  # Acceptance criteria:
  # - Every link URI.parse/1 finds a host in has an authority after "//",
  #   whatever its scheme's case, userinfo, port or brackets: each reads
  #   its host, lower-cased.
  # - So the backslash check, reached only with a host, splits off the
  #   authority without a branch for a link that has none.
  test "a link with a host always has an authority, so the check has no other branch" do
    for {url, host} <- [
          {"https://ir.example/report", "ir.example"},
          {"HTTPS://IR.example", "ir.example"},
          {"//ir.example/protocol-relative", "ir.example"},
          {"https://user:pw@ir.example:8443/a?b#c", "ir.example"},
          {"http://[2001:db8::1]/report", "2001:db8::1"},
          {"ftp://files.example", "files.example"}
        ] do
      assert LinkDomain.of(url) == host, url
    end

    for url <- ["mailto:ir@ir.example", "ir.example/report", "/report", "https:ir.example", ""] do
      assert LinkDomain.of(url) == "link", url
    end

    {:ok, ast} =
      "lib/portfolixir_web/link_domain.ex" |> File.read!() |> Code.string_to_quoted()

    {_ast, bodies} =
      Macro.prewalk(ast, [], fn
        {:defp, _, [{:backslash_in_authority?, _, _} | _]} = node, acc -> {node, [node | acc]}
        node, acc -> {node, acc}
      end)

    assert [body] = bodies

    {_ast, cases} =
      Macro.prewalk(body, 0, fn
        {:case, _, _} = node, n -> {node, n + 1}
        node, n -> {node, n}
      end)

    assert cases == 0, "backslash_in_authority?/1 keeps a branch for a link without an authority"
  end
end
