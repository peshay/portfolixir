defmodule Portfolixir.ApiTokenRefusalRedactionTest do
  # A token written in the wrong place is refused without being echoed
  # (security review 2026-10-12, H22; ADR-0054 §3: "naming the variable, never
  # the token"). Credentials are synthetic and deterministic.
  #
  # async: false -- the release-path test sets environment variables the whole
  # VM reads.
  use ExUnit.Case, async: false

  alias Portfolixir.RuntimeConfig

  # 32 bytes -> 44 base64 characters ending in one "=", the shape of
  # `openssl rand -base64 32` (meets the 32-byte floor).
  @padded Base.encode64(for i <- 1..32, into: <<>>, do: <<rem(i * 37 + 11, 256)>>)
  # 48 bytes -> 64 base64 characters, no "=", the shape of the documented
  # generator `openssl rand -base64 48`.
  @unpadded Base.encode64(for i <- 1..48, into: <<>>, do: <<rem(i * 53 + 7, 256)>>)
  # PORTFOLIXIR_API_TOKEN as Compose passes it (named "mcp"), sound, unrelated.
  @default String.duplicate("t3Zx", 12)

  # What config/runtime.exs needs under :prod to reach the api_tokens! call,
  # each a synthetic value its own check accepts (release_background_fetch_test).
  @release_env %{
    "SECRET_KEY_BASE" => String.duplicate("k7Qm", 16),
    "PHX_HOST" => "portfolixir.example",
    "DATABASE_URL" =>
      "ecto://portfolixir:#{String.duplicate("d8Wq", 16)}@db.example/portfolixir_prod",
    "PORTFOLIXIR_API_TOKEN" => String.duplicate("t3Zx", 12),
    "PORTFOLIXIR_API_PRINCIPAL" => "mcp"
  }

  # The token minus its padding: base64 padding follows from the length alone,
  # so a reader of the log who has this has the whole credential.
  defp body(token), do: String.trim_trailing(token, "=")

  # User story (security review 2026-10-12, H22):
  # As the operator whose boot log is kept and may be shared,
  # I want a malformed PORTFOLIXIR_API_TOKENS entry or PORTFOLIXIR_API_PRINCIPAL
  # refused naming the variable and the entry, never echoing a value that is
  # not name-shaped,
  # so that a token written in the wrong place never lands in the log.
  #
  # Acceptance criteria:
  # - A name-less padded token, as the first or a later entry, a pair written
  #   token=name, and a token in PORTFOLIXIR_API_PRINCIPAL are refused; the
  #   message names the variable (and the entry's position) and carries no
  #   part of the token.
  # - The release boot path's printed error carries no part of the token.
  # - The same tokens, written name=token, boot as named principals.
  test "both synthetic tokens are credentials the boot accepts once named" do
    assert String.ends_with?(@padded, "=") and byte_size(@padded) == 44
    refute String.contains?(@unpadded, "=")

    assert RuntimeConfig.api_tokens!(@default, "scripts=#{@padded}", "mcp") ==
             [{"scripts", @padded}, {"mcp", @default}]

    assert RuntimeConfig.api_tokens!(@default, "scripts=#{@unpadded}", "mcp") ==
             [{"scripts", @unpadded}, {"mcp", @default}]
  end

  test "a name-less padded token in PORTFOLIXIR_API_TOKENS is refused without echoing it" do
    error =
      assert_raise ArgumentError, fn ->
        RuntimeConfig.api_tokens!(@default, @padded, "mcp")
      end

    assert error.message =~ "PORTFOLIXIR_API_TOKENS entry 1"
    assert error.message =~ "name=token"

    refute error.message =~ body(@padded),
           "the boot error carries the token: " <> error.message
  end

  test "a name-less padded token as the second entry is refused without echoing it" do
    error =
      assert_raise ArgumentError, fn ->
        RuntimeConfig.api_tokens!(@default, "scripts=#{@unpadded}, #{@padded}", "mcp")
      end

    assert error.message =~ "PORTFOLIXIR_API_TOKENS entry 2"

    refute error.message =~ body(@padded),
           "the boot error carries the token: " <> error.message
  end

  test "a pair written token=name is refused without echoing the token" do
    error =
      assert_raise ArgumentError, fn ->
        RuntimeConfig.api_tokens!(@default, "#{@unpadded}=scripts", "mcp")
      end

    assert error.message =~ "PORTFOLIXIR_API_TOKENS entry 1"

    refute error.message =~ @unpadded,
           "the boot error carries the token: " <> error.message
  end

  test "a token put into PORTFOLIXIR_API_PRINCIPAL is refused without echoing it" do
    error =
      assert_raise ArgumentError, fn ->
        RuntimeConfig.api_tokens!(@default, nil, @unpadded)
      end

    assert error.message =~ "PORTFOLIXIR_API_PRINCIPAL"

    refute error.message =~ @unpadded,
           "the boot error carries the token: " <> error.message
  end

  test "the release boot path (config/runtime.exs under :prod) prints no token to stderr" do
    env = Map.put(@release_env, "PORTFOLIXIR_API_TOKENS", @padded)

    {error, stacktrace} =
      with_env(env, fn ->
        try do
          Config.Reader.read!("config/runtime.exs", env: :prod, target: :host)
          {:accepted, []}
        rescue
          error in ArgumentError -> {error, __STACKTRACE__}
        end
      end)

    assert %ArgumentError{} = error, "runtime.exs accepted a name-less entry"

    # What Config.Provider.run_providers/2 writes to stderr when a release's
    # runtime.exs raises.
    printed =
      "ERROR! Config provider Config.Reader failed with:\n" <>
        Exception.format(:error, error, stacktrace)

    assert printed =~ "PORTFOLIXIR_API_TOKENS entry 1"
    refute printed =~ body(@padded), "release boot output carries the token:\n" <> printed
  end

  defp with_env(env, fun) do
    previous = Map.new(env, fn {name, _value} -> {name, System.get_env(name)} end)

    try do
      Enum.each(env, fn {name, value} -> put_env(name, value) end)
      fun.()
    after
      Enum.each(previous, fn {name, value} -> put_env(name, value) end)
    end
  end

  defp put_env(name, nil), do: System.delete_env(name)
  defp put_env(name, value), do: System.put_env(name, value)
end
