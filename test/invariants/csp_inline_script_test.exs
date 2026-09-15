defmodule Portfolixir.Invariants.CspInlineScriptTest do
  # Issue #382: the browser pages run under a Content-Security-Policy whose
  # script-src is 'self' plus a per-request nonce. Three things keep that
  # policy honest, pinned at the source so the next inline handler fails the
  # build instead of failing a page silently in the browser.
  use ExUnit.Case, async: true

  # User story:
  # As the maintainer,
  # I want no template to carry an inline event handler or a javascript: URL,
  # so that script-src can stay without 'unsafe-inline' and a control that
  # needs script is wired through a data attribute and the layout's listeners.
  test "no web template carries an inline event handler or a javascript: URL" do
    sources = Path.wildcard("lib/portfolixir_web/**/*.{ex,heex}")
    refute Enum.empty?(sources)

    for path <- sources do
      source = File.read!(path)

      refute Regex.match?(
               ~r/\son(click|change|submit|input|load|error|key[a-z]*|mouse[a-z]*|focus|blur)=/,
               source
             ),
             "#{path} carries an inline event handler"

      refute source =~ ~s(href="javascript:), "#{path} carries a javascript: URL"
    end
  end

  # User story:
  # As the maintainer,
  # I want every executable inline script of the root layout to carry the
  # request's nonce,
  # so that adding a fourth boot script cannot leave it blocked.
  test "every executable inline script of the root layout carries the request nonce" do
    layout = File.read!("lib/portfolixir_web/layout_view.ex")

    inline_tags =
      ~r/<script(?![^>]*\bsrc=)[^>]*>/
      |> Regex.scan(layout)
      |> List.flatten()
      |> Enum.reject(&(&1 =~ ~s(type="application/json")))

    assert length(inline_tags) == 3

    for tag <- inline_tags do
      assert tag =~ "nonce={@csp_nonce}", "#{tag} carries no nonce"
    end
  end

  # User story:
  # As the maintainer,
  # I want both browser pipelines to set the static policy and the nonce plug,
  # so that neither the login page nor a LiveView can lose the header.
  test "both browser pipelines carry the static policy and the nonce plug" do
    router = File.read!("lib/portfolixir_web/router.ex")

    pipelines =
      ~r/pipeline :browser(?:_open)? do.*?\n  end/s
      |> Regex.scan(router)
      |> Enum.map(&hd/1)

    assert length(pipelines) == 2

    for pipeline <- pipelines do
      assert pipeline =~ "plug(:put_secure_browser_headers, @secure_headers)"
      assert pipeline =~ "plug(PortfolixirWeb.ContentSecurityPolicy)"
    end

    assert router =~ ~r/@secure_headers %\{\s*"content-security-policy" =>/
  end
end
