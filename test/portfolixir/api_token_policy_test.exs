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
end
