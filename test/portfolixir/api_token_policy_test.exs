defmodule Portfolixir.ApiTokenPolicyTest do
  use ExUnit.Case, async: true

  alias Portfolixir.RuntimeConfig

  # User story:
  # As an operator starting a production instance (#761),
  # I want a short or placeholder API token refused at boot with the variable named,
  # so that the agent's credential is never the string a public example file shipped.
  #
  # Acceptance criteria:
  # - A token shorter than 32 bytes raises with PORTFOLIXIR_API_TOKEN in the message.
  # - The placeholders from .env.example and the Compose file are refused whatever their length.
  # - A missing token raises the same way; a 32-byte random token is returned unchanged.
  test "refuses short, placeholder and missing tokens and returns a sound one" do
    sound = String.duplicate("k", 32)

    assert RuntimeConfig.validate_api_token!(sound) == sound

    assert_raise ArgumentError, ~r/PORTFOLIXIR_API_TOKEN/, fn ->
      RuntimeConfig.validate_api_token!(String.duplicate("k", 31))
    end

    assert_raise ArgumentError, ~r/PORTFOLIXIR_API_TOKEN/, fn ->
      RuntimeConfig.validate_api_token!(nil)
    end

    for placeholder <- ["dev-api-token", "replace-with-local-api-token", "replace-me", "changeme"] do
      assert_raise ArgumentError, ~r/placeholder/, fn ->
        RuntimeConfig.validate_api_token!(String.pad_trailing(placeholder, 32, "x"))
      end
    end
  end

  # User story (E25 S7, G26, architecture FU-6):
  # As an operator who gives each agent or script its own API token,
  # I want the tokens configured as name–token pairs and each checked at boot
  # like the one token, with PORTFOLIXIR_API_TOKEN still working unnamed,
  # so that the journal can name the token that wrote, an upgrade changes
  # nothing, and a bad entry stops the boot naming the entry, never its token.
  #
  # Acceptance criteria:
  # - PORTFOLIXIR_API_TOKENS "mcp=<token>,scripts=<token>" yields both
  #   principals by name, in order; blank entries and spaces around names and
  #   commas are skipped.
  # - PORTFOLIXIR_API_TOKEN alone is the unnamed default ({nil, token}); with
  #   both set, the named entries come first and the default last.
  # - Refused at boot, naming PORTFOLIXIR_API_TOKENS and the entry: an entry
  #   without "=", a name that is not 1 to 32 of a-z, 0-9, "_" and "-"
  #   starting with a letter or digit, a name used twice, a short or
  #   placeholder token; a token given twice, across both variables too.
  # - Neither set: refused naming both variables.
  test "named tokens are name–token pairs, checked like the one token" do
    mcp = String.duplicate("m", 40)
    scripts = String.duplicate("s", 40)
    default = String.duplicate("d", 40)

    assert RuntimeConfig.api_tokens!(nil, " mcp=#{mcp}, ,scripts=#{scripts},") ==
             [{"mcp", mcp}, {"scripts", scripts}]

    assert RuntimeConfig.api_tokens!(default, nil) == [{nil, default}]
    assert RuntimeConfig.api_tokens!(default, "") == [{nil, default}]

    assert RuntimeConfig.api_tokens!(default, "mcp=#{mcp}") == [{"mcp", mcp}, {nil, default}]

    # A token keeps every character after the first "=", its own "=" included.
    padded = String.duplicate("p", 38) <> "=="
    assert RuntimeConfig.api_tokens!(nil, "mcp=#{padded}") == [{"mcp", padded}]

    refusals = [
      {"mcp#{mcp}", ~r/PORTFOLIXIR_API_TOKENS.*entry 1.*name=token/},
      {"MCP=#{mcp}", ~r/PORTFOLIXIR_API_TOKENS.*"MCP"/},
      {"-x=#{mcp}", ~r/PORTFOLIXIR_API_TOKENS.*"-x"/},
      {"#{String.duplicate("n", 33)}=#{mcp}", ~r/PORTFOLIXIR_API_TOKENS/},
      {"mcp=#{mcp},mcp=#{scripts}", ~r/PORTFOLIXIR_API_TOKENS.*"mcp".*twice/},
      {"mcp=short", ~r/PORTFOLIXIR_API_TOKENS.*"mcp".*32 bytes/},
      {"mcp=" <> String.pad_trailing("replace-me", 40, "x"), ~r/"mcp".*placeholder/},
      {"mcp=#{mcp},scripts=#{mcp}", ~r/PORTFOLIXIR_API_TOKENS.*"scripts".*same token/}
    ]

    for {value, message} <- refusals do
      error = assert_raise ArgumentError, fn -> RuntimeConfig.api_tokens!(nil, value) end
      assert error.message =~ message, value
      refute error.message =~ mcp
    end

    assert_raise ArgumentError, ~r/PORTFOLIXIR_API_TOKEN the same token as "mcp"/, fn ->
      RuntimeConfig.api_tokens!(mcp, "mcp=#{mcp}")
    end

    assert_raise ArgumentError, ~r/PORTFOLIXIR_API_TOKEN or PORTFOLIXIR_API_TOKENS/, fn ->
      RuntimeConfig.api_tokens!(nil, " , ")
    end

    # The single token keeps its own refusals and its own variable's name.
    assert_raise ArgumentError, ~r/^PORTFOLIXIR_API_TOKEN must be/, fn ->
      RuntimeConfig.api_tokens!("short", "mcp=#{mcp}")
    end

    runtime = File.read!("config/runtime.exs")

    assert runtime =~
             ~r/config :portfolixir,\s+:api_tokens,\s+Portfolixir.RuntimeConfig.api_tokens!\(/

    assert runtime =~ ~s[System.get_env("PORTFOLIXIR_API_TOKENS")]
  end

  # User story (E25 S1, F01):
  # As a maintainer,
  # I want the MCP companion's token policy pinned to the API token's,
  # so that one credential's policy cannot silently drift from the other's.
  #
  # Acceptance criteria:
  # - The companion's length floor equals the API token's.
  # - The companion's placeholder prefixes equal the API token's, in order.
  test "the MCP companion's token policy is the API token's" do
    source = File.read!("mcp-server/src/http.ts")

    [_, floor] = Regex.run(~r/MCP_TOKEN_MIN_BYTES = (\d+);/, source)
    assert String.to_integer(floor) == RuntimeConfig.min_token_bytes()

    [_, list] = Regex.run(~r/MCP_TOKEN_PLACEHOLDER_PREFIXES = \[(.*?)\];/s, source)
    prefixes = ~r/"([^"]+)"/ |> Regex.scan(list) |> Enum.map(&List.last/1)
    assert prefixes == RuntimeConfig.token_placeholder_prefixes()
  end
end
