defmodule PortfolixirWeb.ShippedFontTest do
  # Sprint 30 F1 (#1221; plan D-4, board ux-design-2026-11-15-sprint30/03):
  # `--font-sans` named Inter first, but the app shipped no font file, so
  # every width floor depended on the reader's system font. The app now
  # ships the variable Inter (wght 100–900), latin and latin-ext, normal and
  # italic, as woff2 under priv/static/fonts/ with its licence beside them,
  # from @fontsource-variable/inter 5.3.0.
  use PortfolixirWeb.ConnCase, async: true

  @fonts_dir "priv/static/fonts"
  @version "5.3.0"

  # The shipped files and their sha256, as the commit that added them
  # recorded them from the npm tarball whose sha512 integrity it checked. A
  # file swapped or re-encoded without a new pin fails here.
  @files %{
    "inter-latin-wght-normal.woff2" =>
      "3100e775e8616cd2611beecfa23a4263d7037586789b43f035236a2e6fbd4c62",
    "inter-latin-ext-wght-normal.woff2" =>
      "34b9c504cab7a73e37b746343a449132e56cf7b5481af2cb81dc74dcff25c956",
    "inter-latin-wght-italic.woff2" =>
      "7291b5970da2237441273c03b424a504b70b18f09791473fab99687dcc314720",
    "inter-latin-ext-wght-italic.woff2" =>
      "71254244ccb1ec21e14db3480fef6f6826d1136dc4aca1c7d3ca7ce31294fcce",
    "OFL.txt" => "3b0a5fca3d17942cde889069889dedbbbd075e9b599968c82a95f4d944e9b345"
  }

  # User story (Sprint 30 F1, #1221):
  # As an operator on a device without Inter installed,
  # I want the app to bring its own Inter, served by my own instance,
  # so that every page reads as it was measured, and no request leaves my
  # machine for a font.
  #
  # Acceptance criteria:
  # - GET /fonts/inter-latin-wght-normal.woff2 answers 200 font/woff2 with
  #   the static assets' headers (nosniff, same-origin resource policy).
  # - Asked as app.css names it (`?vsn=<pinned version>`), the font is
  #   cached for a year and immutable: the version in the URL changes when
  #   the file does.
  # - Every shipped file is the pinned one, byte for byte (sha256).
  # - The licence ships beside the fonts and is served at /fonts/OFL.txt,
  #   and the README's third-party notice names it.
  test "the app serves its own Inter, pinned, with long cache headers and its licence",
       %{conn: conn} do
    font = get(conn, "/fonts/inter-latin-wght-normal.woff2")
    assert font.status == 200
    assert [content_type] = get_resp_header(font, "content-type")
    assert content_type =~ "font/woff2"
    assert get_resp_header(font, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(font, "cross-origin-resource-policy") == ["same-origin"]
    assert <<"wOF2", _rest::binary>> = font.resp_body

    versioned = get(build_conn(), "/fonts/inter-latin-wght-normal.woff2?vsn=#{@version}")
    assert versioned.status == 200

    assert get_resp_header(versioned, "cache-control") == [
             "public, max-age=31536000, immutable"
           ]

    for {file, sha256} <- @files do
      path = Path.join(@fonts_dir, file)
      assert File.exists?(path), "#{path} is not shipped"

      assert :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower) == sha256,
             path
    end

    licence = get(build_conn(), "/fonts/OFL.txt")
    assert licence.status == 200
    assert licence.resp_body =~ "SIL OPEN FONT LICENSE Version 1.1"
    assert licence.resp_body =~ "The Inter Project Authors"

    readme = File.read!("README.md")
    assert readme =~ "### Third-party notices"
    assert readme =~ ~r/SIL Open Font\s+License 1\.1/
    assert readme =~ "priv/static/fonts/OFL.txt"

    assert @fonts_dir |> File.ls!() |> Enum.sort() == @files |> Map.keys() |> Enum.sort(),
           "priv/static/fonts holds a file the pin does not name"
  end

  # Acceptance criteria:
  # - app.css declares one @font-face per shipped woff2, family Inter,
  #   `font-display: swap` (a slow file never hides text), `font-weight:
  #   100 900`, its subset's `unicode-range`, and a src under /fonts/ at the
  #   pinned version, the only src it names.
  # - `--font-sans` keeps Inter first and the fallback stack after it.
  test "app.css declares each shipped face with swap, its weight range and its unicode-range" do
    css = File.read!("priv/static/app.css")
    faces = Regex.scan(~r/@font-face\s*\{([^}]*)\}/, css, capture: :all_but_first)
    woff2 = @files |> Map.keys() |> Enum.filter(&String.ends_with?(&1, ".woff2"))

    assert length(faces) == length(woff2)

    for [face] <- faces do
      assert face =~ ~r/font-family:\s*"Inter";/
      assert face =~ ~r/font-display:\s*swap;/
      assert face =~ ~r/font-weight:\s*100 900;/
      assert face =~ ~r/unicode-range:\s*U\+/

      assert [[file, style]] =
               Regex.scan(
                 ~r{url\("/fonts/(inter-[a-z-]+-wght-(normal|italic)\.woff2)\?vsn=#{Regex.escape(@version)}"\)},
                 face,
                 capture: :all_but_first
               )

      assert file in woff2
      assert face =~ ~r/font-style:\s*#{style};/
      refute face =~ "local("
    end

    assert css =~
             ~s(--font-sans: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;)
  end
end
