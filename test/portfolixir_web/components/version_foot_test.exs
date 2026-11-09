defmodule PortfolixirWeb.Components.VersionFootTest do
  # FR-55 (#1429), Sprint 28 V2, board
  # `ux-design-2026-11-08-sprint28/04-version` (plan D-6): the version at the
  # foot of the sidebar, which on a phone is the bottom of the menu sheet.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest

  alias Portfolixir.BuildVersion
  alias PortfolixirWeb.AppShell

  @commit "3cba116e0f4a5b6c7d8e9f00112233445566778a"
  @css File.read!("priv/static/app.css")

  defp version(kind) do
    case kind do
      :release -> BuildVersion.resolve(%{"PORTFOLIXIR_VERSION" => "2026.11.12"}, nil)
      :build -> BuildVersion.resolve(%{}, git())
      :unknown -> BuildVersion.resolve(%{}, nil)
    end
  end

  defp git do
    %{commit: @commit, branch: "main", tag: nil, committed_on: ~D[2026-11-08]}
  end

  defp foot(version, locale) do
    previous = Gettext.get_locale(PortfolixirWeb.Gettext)
    Gettext.put_locale(PortfolixirWeb.Gettext, locale)

    try do
      assigns = %{version: version}
      html = rendered_to_string(~H"<AppShell.version_foot version={@version} />")

      [foot] =
        html |> LazyHTML.from_fragment() |> LazyHTML.query("#sidebar-version") |> Enum.to_list()

      foot
    after
      Gettext.put_locale(PortfolixirWeb.Gettext, previous)
    end
  end

  defp text(node), do: node |> LazyHTML.text() |> String.replace(~r/\s+/, " ") |> String.trim()

  # A link's text without its arrow, which is aria-hidden.
  defp link_text(link) do
    [arrow] = link |> LazyHTML.query(".sidebar-version__ext") |> Enum.to_list()
    assert attr(arrow, "aria-hidden") == "true"
    assert text(arrow) == "↗"
    link |> text() |> String.trim_trailing("↗")
  end

  defp attr(node, name), do: node |> LazyHTML.attribute(name) |> List.first()

  defp rule(selector) do
    case Regex.run(~r/(?:^|\n)#{Regex.escape(selector)} \{([^}]*)\}/, @css) do
      [_, body] -> body
      nil -> flunk("no rule for #{selector}")
    end
  end

  # User story (FR-55, board 04 ①):
  # As the operator looking at the menu,
  # I want its foot to name the version this instance was built from,
  # linked to what explains it,
  # so that I know which release is installed, and can read its notes.
  #
  # Acceptance criteria:
  # - A small label "Version" over the value; the value in monospace.
  # - A release reads its calendar tag and links its release notes on
  #   GitHub; a build reads branch · short hash · the commit date in the
  #   page's language and links the commit; unknown reads "unknown"
  #   („unbekannt“), in italics, and links nothing.
  # - A link opens in a new tab with no referrer: the operator follows it,
  #   the page loads nothing from GitHub.
  describe "the foot, each kind" do
    test "a release links its release notes" do
      foot = foot(version(:release), "de")
      [link] = foot |> LazyHTML.query("a") |> Enum.to_list()

      assert text(foot |> LazyHTML.query(".sidebar-version__label")) == "Version"
      assert link_text(link) == "2026.11.12"
      assert attr(link, "href") == "https://github.com/peshay/portfolixir/releases/tag/2026.11.12"
      assert attr(link, "title") == "Versionshinweise auf GitHub"
      assert attr(link, "rel") == "noopener noreferrer"
      assert attr(link, "target") == "_blank"
      assert attr(link, "class") =~ "sidebar-version__text"
    end

    test "a build links its commit, its date in the page's language" do
      foot = foot(version(:build), "de")
      [link] = foot |> LazyHTML.query("a") |> Enum.to_list()

      assert link_text(link) == "main · 3cba116 · 08.11.2026"
      assert attr(link, "href") == "https://github.com/peshay/portfolixir/commit/#{@commit}"
      assert attr(link, "title") == "Commit auf GitHub"

      english = foot(version(:build), "en")
      assert link_text(english |> LazyHTML.query("a")) == "main · 3cba116 · 2026-11-08"
      assert attr(english |> LazyHTML.query("a"), "title") == "Commit on GitHub"
    end

    test "unknown is italic and links nothing" do
      foot = foot(version(:unknown), "de")

      assert foot |> LazyHTML.query("a") |> Enum.to_list() == []
      [value] = foot |> LazyHTML.query(".sidebar-version__text") |> Enum.to_list()
      assert text(value) == "unbekannt"
      assert attr(value, "class") =~ "sidebar-version__unknown"

      assert text(foot(version(:unknown), "en") |> LazyHTML.query(".sidebar-version__text")) ==
               "unknown"
    end

    test "the anatomy: a hairline above, the label small over the value, the value in monospace" do
      assert rule(".sidebar-version") =~ "border-top: 1px solid var(--color-border);"
      assert rule(".sidebar-version") =~ "display: grid;"
      assert rule(".sidebar-version__label") =~ "text-transform: uppercase;"
      assert rule(".sidebar-version__text") =~ "font-family: var(--font-mono);"
      assert rule(".sidebar-version__unknown") =~ "font-style: italic;"
    end
  end

  # User story (FR-55, board 04 ① and ②):
  # As the operator on any page, on a desk or on a phone,
  # I want the foot in the menu itself, under „Abmelden“ when the login is
  # on, and not in the top bar,
  # so that it is where the board puts it and the phone's menu sheet shows
  # it at its bottom.
  #
  # Acceptance criteria:
  # - A shell page renders the compiled version's foot as the sidebar's last
  #   child; the phone's menu is that sidebar opened, so it is there too.
  test "the shell carries the compiled version at the sidebar's foot", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    document = LazyHTML.from_document(html)

    [sidebar] = document |> LazyHTML.query("#app-sidebar") |> Enum.to_list()

    assert [_foot] =
             sidebar
             |> LazyHTML.query("#app-sidebar > #sidebar-version:last-child")
             |> Enum.to_list()

    assert document |> LazyHTML.query(".topbar #sidebar-version") |> Enum.to_list() == []

    current = BuildVersion.current()
    value = text(sidebar |> LazyHTML.query(".sidebar-version__text"))

    case current.kind do
      :unknown -> assert value in ["unknown", "unbekannt"]
      :release -> assert value =~ current.value
      :build -> assert value =~ BuildVersion.short(current.commit)
    end
  end

  # User story (plan D-8, carry-forward 2; D-1 criterion 9, "the screen
  # makes no request"):
  # As the operator whose instance calls out only where B2 registered it,
  # I want the foot to be a link and nothing the page loads,
  # so that GitHub hears of my instance only when I follow the link.
  #
  # Acceptance criteria:
  # - The foot holds no element that loads a resource (no src, srcset,
  #   poster, data, a stylesheet or a prefetch), only the one link.
  # - The shell's compiled calls include no HTTP client, socket or
  #   subprocess.
  test "the foot is a link to follow, and the shell requests nothing" do
    for kind <- [:release, :build, :unknown] do
      foot = foot(version(kind), "en")

      assert foot
             |> LazyHTML.query("[src], [srcset], [poster], [data], link, img, script, iframe")
             |> Enum.to_list() ==
               []

      links = foot |> LazyHTML.query("a") |> Enum.to_list()
      assert length(links) == if(kind == :unknown, do: 0, else: 1)
    end

    {:ok, {AppShell, [imports: imports]}} =
      AppShell |> beam_file() |> :beam_lib.chunks([:imports])

    outbound =
      Enum.filter(imports, fn {module, function, _arity} ->
        name = Atom.to_string(module)

        module in [:httpc, :gen_tcp, :ssl, :socket] or
          String.starts_with?(name, ["Elixir.Req", "Elixir.Finch", "Elixir.Mint"]) or
          name == "Elixir.Portfolixir.Net.Http" or
          {module, function} in [{System, :cmd}, {:os, :cmd}, {:erlang, :open_port}]
      end)

    assert outbound == []
  end

  # The compiled .beam on disk: under `mix test --cover` (CI's coveralls run)
  # `:code.which/1` answers `:cover_compiled`, not a path, so the file is
  # looked up in the code path by its name.
  defp beam_file(module), do: :code.where_is_file(~c"#{module}.beam")
end
