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

  # User story (E25 S7 review round, S7E-5):
  # As an operator upgrading a Compose deployment whose PORTFOLIXIR_API_TOKEN
  # the old check accepted — one with a comma, or with a space at an edge —
  # I want the app to take that token as it is and still name it "mcp",
  # so that the upgrade neither stops the boot nor leaves the companion's
  # token unmatched.
  #
  # Acceptance criteria:
  # - PORTFOLIXIR_API_PRINCIPAL names PORTFOLIXIR_API_TOKEN: the default
  #   becomes {name, token}, the token taken whole, checked only by
  #   validate_api_token!/1 as before; unset or blank, it stays unnamed.
  # - Its name follows the entry names' rule; a name PORTFOLIXIR_API_TOKENS
  #   uses too, or a name with no PORTFOLIXIR_API_TOKEN to name, stops the
  #   boot naming the variable, never a token.
  # - Compose passes the token through PORTFOLIXIR_API_TOKEN and names it
  #   "mcp" through PORTFOLIXIR_API_PRINCIPAL; runtime.exs reads all three.
  test "the one token is named by its own variable and taken whole" do
    comma = String.duplicate("c", 20) <> "," <> String.duplicate("d", 20)
    edged = " " <> String.duplicate("e", 40) <> " "
    scripts = String.duplicate("s", 40)

    assert RuntimeConfig.api_tokens!(comma, nil, "mcp") == [{"mcp", comma}]
    assert RuntimeConfig.api_tokens!(edged, "", " mcp ") == [{"mcp", edged}]

    assert RuntimeConfig.api_tokens!(comma, "scripts=#{scripts}", "mcp") ==
             [{"scripts", scripts}, {"mcp", comma}]

    assert RuntimeConfig.api_tokens!(comma, nil, nil) == [{nil, comma}]
    assert RuntimeConfig.api_tokens!(comma, nil, "") == [{nil, comma}]

    refusals = [
      {{comma, nil, "MCP"}, ~r/^PORTFOLIXIR_API_PRINCIPAL.*"MCP"/},
      {{comma, "mcp=#{scripts}", "mcp"},
       ~r/PORTFOLIXIR_API_PRINCIPAL and PORTFOLIXIR_API_TOKENS both name "mcp"/},
      {{nil, "scripts=#{scripts}", "mcp"}, ~r/^PORTFOLIXIR_API_PRINCIPAL.*not set/},
      {{"short", nil, "mcp"}, ~r/^PORTFOLIXIR_API_TOKEN must be/}
    ]

    for {{single, named, name}, message} <- refusals do
      error =
        assert_raise ArgumentError, fn -> RuntimeConfig.api_tokens!(single, named, name) end

      assert error.message =~ message
      refute error.message =~ comma
      refute error.message =~ scripts
    end

    runtime = File.read!("config/runtime.exs")
    assert runtime =~ ~s[System.get_env("PORTFOLIXIR_API_PRINCIPAL")]

    compose = File.read!("docker-compose.yml")
    [app_service] = Regex.run(~r/^  app:\n(?:    .*\n|\n)*/m, compose)

    assert app_service =~
             "PORTFOLIXIR_API_TOKEN: ${PORTFOLIXIR_API_TOKEN:?set PORTFOLIXIR_API_TOKEN in .env}"

    assert app_service =~ ~r/^      PORTFOLIXIR_API_PRINCIPAL: mcp$/m
    assert app_service =~ "PORTFOLIXIR_API_TOKENS: ${PORTFOLIXIR_API_TOKENS:-}"
    refute app_service =~ "mcp=${PORTFOLIXIR_API_TOKEN"
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
