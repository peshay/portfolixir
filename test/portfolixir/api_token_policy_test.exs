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
