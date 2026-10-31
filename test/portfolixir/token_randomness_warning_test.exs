defmodule Portfolixir.TokenRandomnessWarningTest do
  # The token floor checks length only; a token that is plainly not random is
  # named at startup (security review 2026-10-12, H20; #1202; T-17).
  #
  # async: false -- it sets the application environment warn_if_exposed/0
  # reads.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  # Synthetic, deterministic: 48 bytes as `openssl rand -base64 48` prints them.
  @random Base.encode64(for i <- 1..48, into: <<>>, do: <<rem(i * 53 + 7, 256)>>)
  @repeated String.duplicate("a", 32)
  @counting String.duplicate("0123456789", 3) <> "01"

  setup do
    previous = Application.fetch_env(:portfolixir, :api_tokens)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:portfolixir, :api_tokens, value)
        :error -> Application.delete_env(:portfolixir, :api_tokens)
      end
    end)

    :ok
  end

  defp boot_log(principals) do
    Application.put_env(:portfolixir, :api_tokens, principals)

    capture_log([level: :warning], fn ->
      assert Portfolixir.Application.warn_if_exposed() == :ok
    end)
  end

  # User story (security review 2026-10-12, H20; #1202; T-17):
  # As the operator who sets the API tokens,
  # I want a token with few distinct characters named in a startup warning,
  # so that a hand-typed token the length floor accepts does not pass for a
  # random one, now that the lock no longer slows guessing.
  #
  # Acceptance criteria:
  # - A configured token of one repeated character, or of a counting run,
  #   meets the 32-byte floor and boots, and is named in a warning by its
  #   variable or its name; the warning never carries the token and says how
  #   to generate one.
  # - A token generated as documented is named in no such warning.
  test "a token with few distinct characters is named in a startup warning, never shown" do
    assert Portfolixir.RuntimeConfig.api_tokens!(@repeated, "scripts=#{@counting}") ==
             [{"scripts", @counting}, {nil, @repeated}]

    log = boot_log([{"scripts", @counting}, {"mcp", @random}, {nil, @repeated}])

    assert log =~ "PORTFOLIXIR_API_TOKEN"
    assert log =~ ~s("scripts")
    refute log =~ ~s("mcp")
    assert log =~ "openssl rand -base64 48"
    refute log =~ @repeated
    refute log =~ @counting

    refute boot_log([{"mcp", @random}]) =~ "distinct"
  end
end
