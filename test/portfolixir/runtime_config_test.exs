defmodule Portfolixir.RuntimeConfigTest do
  use ExUnit.Case, async: true

  # User story:
  # As an operator running Portfolixir in internal Compose,
  # I want database SSL to default off while still being configurable,
  # so that app-to-Postgres traffic inside the Compose network does not require TLS.
  #
  # Acceptance criteria:
  # - DATABASE_SSL defaults to false.
  # - The accepted true values are 1, true, and yes.
  # - Other values are parsed as false.
  test "parses DATABASE_SSL with a false default and explicit true values" do
    refute Portfolixir.RuntimeConfig.database_ssl?(nil)
    refute Portfolixir.RuntimeConfig.database_ssl?("")
    refute Portfolixir.RuntimeConfig.database_ssl?("false")
    refute Portfolixir.RuntimeConfig.database_ssl?("no")

    assert Portfolixir.RuntimeConfig.database_ssl?("1")
    assert Portfolixir.RuntimeConfig.database_ssl?("true")
    assert Portfolixir.RuntimeConfig.database_ssl?("TRUE")
    assert Portfolixir.RuntimeConfig.database_ssl?("yes")
  end
end
