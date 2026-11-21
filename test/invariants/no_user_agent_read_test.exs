defmodule Portfolixir.Invariants.NoUserAgentReadTest do
  # Sprint 31 D3 (ADR-0062 §6; plan D-1 exit criterion 4): the available
  # width picks the layout, never the device. The class — compact, medium,
  # wide — is chosen in CSS by the window's width and height, so a new
  # device falls into a class by its size and no device list stands in the
  # code. This meta-test keeps every read of the user agent out of the web
  # layer and the scripts it ships (inline in `layout_view.ex`, and
  # `priv/static`): the request header, a socket's
  # connect info and the browser's `navigator.userAgent` alike.
  #
  # The outbound clients in `lib/portfolixir/` SET a user agent on their
  # own requests; that is no read of the operator's device, and the scan
  # covers the web layer only.
  use ExUnit.Case, async: true

  @sources ["lib/portfolixir_web/**/*.{ex,exs,heex}", "priv/static/**/*.js"]

  # The spellings a read of the device takes: the header (`user-agent`),
  # the connect-info key and Plug's helpers (`user_agent`), the browser's
  # properties (`userAgent`, `userAgentData`). Case-insensitive, so
  # `User-Agent` counts too.
  @read ~r/user[-_]?agent/i

  # User story:
  # As the operator opening a dashboard on a phone, a folding phone or a
  # split screen,
  # I want the layout picked by the space the window has,
  # so that a device the code has never heard of still gets the right
  # layout.
  #
  # Acceptance criteria:
  # - No file of the web layer or of the shipped scripts names the user
  #   agent: no request header read, no connect info, no `navigator`
  #   property.
  # - The check finds a planted read in each of its forms (the attack
  #   case), so it checks what it says.
  test "the web layer reads no user agent" do
    files = Enum.flat_map(@sources, &Path.wildcard/1)

    # Not vacuous: the scan reads the dashboard page, the layout that ships
    # the hooks' script inline and the theme's boot script.
    assert "lib/portfolixir_web/live/dashboard_live.ex" in files
    assert "lib/portfolixir_web/layout_view.ex" in files
    assert "priv/static/theme-boot.js" in files

    offenders = for path <- files, line <- reads(File.read!(path)), do: "#{path}:#{line}"

    assert offenders == [],
           "The width picks the layout, never the device (ADR-0062 §6); remove:\n" <>
             Enum.join(offenders, "\n")
  end

  test "a planted read of the user agent is refused" do
    assert reads(~s|defmodule A do\n  def ua(conn), do: get_req_header(conn, "user-agent")\nend|) ==
             [2]

    assert reads(
             ~s|socket "/live", Phoenix.LiveView.Socket,\n  websocket: [connect_info: [:user_agent]]|
           ) ==
             [2]

    assert reads("const phone = /iPhone/.test(navigator.userAgent);") == [1]
    assert reads("if (navigator.userAgentData.mobile) {}") == [1]
    assert reads(~s|get_req_header(conn, "User-Agent")|) == [1]

    assert reads("the width picks the layout; no device is detected") == []
  end

  defp reads(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _number} -> Regex.match?(@read, line) end)
    |> Enum.map(fn {_line, number} -> number end)
  end
end
