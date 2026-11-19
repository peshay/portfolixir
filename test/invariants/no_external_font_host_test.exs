defmodule Portfolixir.Invariants.NoExternalFontHostTest do
  use ExUnit.Case, async: true

  # Sprint 30 F1 (#1221; plan D-4, D-1 criterion 1): the app ships its own
  # Inter, and no page may ask another host for a font or a stylesheet. The
  # CSP's `font-src 'self'` would refuse such a font in the browser, but
  # only after the page asked: the request itself would already have told
  # a font host that this instance was opened, and from where. So the
  # sources are read here: every stylesheet and script the endpoint serves,
  # and every module of the web layer (the layouts and templates).
  #
  # What it refuses:
  # - in a stylesheet, a `url(…)` or an `@import` that names a scheme other
  #   than `data:` or starts with `//` (another origin);
  # - in a stylesheet, a script or a template, a known web-font host's name;
  # - in a template, a `<link>` whose `href` names another origin.
  #
  # Runs in the test job: it reads files and needs no browser.

  @font_hosts ~w(
    fonts.googleapis.com fonts.gstatic.com use.typekit.net p.typekit.net
    fonts.bunny.net rsms.me fonts.cdnfonts.com fast.fonts.net
    cdn.jsdelivr.net unpkg.com cdnjs.cloudflare.com
  )

  # A CSS url() or @import target, quoted or not.
  @css_url ~r/(?:url\(\s*["']?|@import\s+["'])([^"')\s]+)/
  # A <link …> tag's href.
  @link_href ~r/<link\b[^>]*\bhref=["']([^"']+)["']/

  # User story (Sprint 30 F1, #1221):
  # As an operator who runs the instance on my own machine,
  # I want no page to fetch a font or a stylesheet from another host,
  # so that opening the app tells no font service that I did.
  #
  # Acceptance criteria:
  # - No stylesheet under priv/static names an external url() or @import.
  # - No stylesheet, script or web-layer module names a web-font host.
  # - No template links a stylesheet, a font or an icon on another origin.
  test "no page asks another host for a font or a stylesheet" do
    files =
      Path.wildcard("priv/static/**/*.{css,js}") ++
        Path.wildcard("lib/portfolixir_web/**/*.{ex,heex,eex}")

    assert Enum.any?(files, &String.ends_with?(&1, "priv/static/app.css"))

    found = for file <- files, violation <- violations(file, File.read!(file)), do: violation

    assert found == [],
           "a page would ask another host for a font or a stylesheet:\n" <>
             Enum.join(found, "\n")
  end

  # The attack cases: each way of reaching another host is refused, so a
  # clean tree cannot pass vacuously.
  test "the check refuses an external font, stylesheet or link" do
    assert violations("app.css", ~s|@font-face { src: url("/fonts/a.woff2?vsn=1"); }|) == []
    assert violations("app.css", ~s|.a { background: url("data:image/svg+xml,x"); }|) == []
    assert violations("app.css", ~s|.a { mask: url(#clip); }|) == []
    assert violations("layout.ex", ~s|<link rel="stylesheet" href="/app.css" />|) == []

    refused = [
      {"app.css", ~s|@font-face { src: url(https://example.test/inter.woff2); }|},
      {"app.css", ~s|@font-face { src: url('//example.test/inter.woff2'); }|},
      {"app.css", ~s|@import "https://example.test/fonts.css";|},
      {"app.css", ~s|@import url(http://example.test/fonts.css);|},
      {"theme.js", ~s|const href = "https://fonts.googleapis.com/css2?family=Inter";|},
      {"layout.ex", ~s|<link rel="preconnect" href="https://fonts.gstatic.com" />|},
      {"layout.ex", ~s|<link rel="stylesheet" href="//example.test/inter.css" />|},
      {"layout.ex", ~s|<link href="http://example.test/a.css" rel="stylesheet">|}
    ]

    for {file, source} <- refused do
      assert violations(file, source) != [], "not refused: #{source}"
    end
  end

  defp violations(file, source) do
    css =
      if String.ends_with?(file, ".css") do
        for [target] <- Regex.scan(@css_url, source, capture: :all_but_first),
            external?(target),
            do: "#{file}: #{target}"
      else
        []
      end

    hosts =
      for host <- @font_hosts, String.contains?(source, host), do: "#{file}: names #{host}"

    links =
      if String.ends_with?(file, [".ex", ".heex", ".eex"]) do
        for [href] <- Regex.scan(@link_href, source, capture: :all_but_first),
            external?(href),
            do: "#{file}: <link href=#{href}>"
      else
        []
      end

    css ++ hosts ++ links
  end

  defp external?("//" <> _), do: true

  defp external?(target) do
    case Regex.run(~r/^([a-zA-Z][a-zA-Z0-9+.-]*):/, target) do
      [_, scheme] -> String.downcase(scheme) != "data"
      nil -> false
    end
  end
end
