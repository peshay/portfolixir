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
  # A synthetic token that passes the name rule (32 lowercase hex characters,
  # what `openssl rand -hex 16` prints).
  @hex_token "3f9a1c0b7e2d4a6f8b1c3e5d7f9a0b2c"
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

  # User story (#1262, the Shell polish list #1357; Sprint 30 plan, F2):
  # As the operator whose boot log is kept and may be shared,
  # I want a pair written token=name refused without the token, even when the
  # token happens to pass the name rule,
  # so that a swapped pair never prints my token as if it were the name.
  #
  # Acceptance criteria:
  # - A token of 32 lowercase hex characters written token=name is refused
  #   naming the variable and the entry's position, telling the length of
  #   the left side and hinting at a swapped pair, never quoting it.
  test "a name-shaped token written token=name is refused without echoing the token" do
    hex = Base.encode16(for(i <- 1..16, into: <<>>, do: <<rem(i * 29 + 3, 256)>>), case: :lower)
    assert byte_size(hex) == RuntimeConfig.min_token_bytes()
    assert hex =~ ~r/^[a-z0-9][a-z0-9_-]{0,31}$/

    error =
      assert_raise ArgumentError, fn ->
        RuntimeConfig.api_tokens!(@default, "scripts=#{@unpadded}, #{hex}=scripts", "mcp")
      end

    assert error.message =~ "PORTFOLIXIR_API_TOKENS entry 2"
    assert error.message =~ "32 characters"
    assert error.message =~ "name=token"
    refute error.message =~ hex, "the boot error carries the token: " <> error.message
  end

  # User story (Sprint 30 closing act, security lens, finding 2; #1262):
  # As the operator whose boot log is kept and may be shared,
  # I want a pair written token=name whose name is 32 characters, the
  # longest a name may be, never to print the token, whether the boot
  # refuses it or warns about it,
  # so that a swapped pair the length floor cannot tell apart never puts my
  # token into the log.
  #
  # Acceptance criteria:
  # - A swapped pair whose name starts like a placeholder is refused naming
  #   the variable, the entry's position and the name's length, never the
  #   name.
  # - A swapped pair the boot accepts, whose name has few distinct
  #   characters, is named in the startup warning by its place, never by its
  #   name.
  # - A refusal for a name given twice, or for a token given under two
  #   names, never quotes a name of 32 characters.
  test "a swapped pair whose 32-character name starts like a placeholder never prints the token" do
    error =
      assert_raise ArgumentError, fn ->
        RuntimeConfig.api_tokens!(nil, @hex_token <> "=secret-reader-agent-workstation1")
      end

    assert error.message =~ "PORTFOLIXIR_API_TOKENS entry 1"
    assert error.message =~ "placeholder"
    assert error.message =~ "32 characters"
    refute error.message =~ @hex_token, "the boot error carries the token: " <> error.message
  end

  test "a swapped pair the boot accepts is warned about by its place, never by its name" do
    weak_name = "reader-reader-reader-reader-read"
    assert byte_size(weak_name) == RuntimeConfig.min_token_bytes()

    principals =
      RuntimeConfig.api_tokens!(@default, "scripts=#{@unpadded}, #{@hex_token}=#{weak_name}")

    assert principals == [{"scripts", @unpadded}, {@hex_token, weak_name}, {nil, @default}]

    assert {:warn, message} = RuntimeConfig.weak_tokens_warning(principals)
    assert message =~ "configured token 2"
    refute message =~ @hex_token, "the warning carries the token: " <> message
    refute message =~ weak_name
  end

  test "a refusal naming a repeated name or token never quotes a 32-character name" do
    for {named, principal} <- [
          {"#{@hex_token}=#{@unpadded}, #{@hex_token}=#{body(@padded)}", nil},
          {"#{@hex_token}=#{@unpadded}, scripts=#{@unpadded}", nil},
          {"scripts=#{@unpadded}, #{@hex_token}=#{@unpadded}", nil},
          {"#{@hex_token}=#{@unpadded}", @hex_token}
        ] do
      error =
        assert_raise ArgumentError, fn ->
          RuntimeConfig.api_tokens!(@default, named, principal)
        end

      refute error.message =~ @hex_token, "the boot error carries the token: " <> error.message
    end
  end

  # A URL-safe token of exactly the floor's length (what
  # `secrets.token_urlsafe(24)` prints) is shaped like a name but fails the
  # name rule: it is never quoted, in either variable.
  test "a floor-length name-shaped value is never quoted" do
    floor_length = "AbCdEfGhIjKlMnOpQrStUvWxYz012345"
    assert byte_size(floor_length) == RuntimeConfig.min_token_bytes()

    principal =
      assert_raise ArgumentError, fn ->
        RuntimeConfig.api_tokens!(@default, nil, floor_length)
      end

    assert principal.message =~ "PORTFOLIXIR_API_PRINCIPAL"
    refute principal.message =~ floor_length, "the boot error carries the token"

    entry =
      assert_raise ArgumentError, fn ->
        RuntimeConfig.api_tokens!(@default, "#{floor_length}=scripts", "mcp")
      end

    assert entry.message =~ "PORTFOLIXIR_API_TOKENS entry 1"
    refute entry.message =~ floor_length, "the boot error carries the token"
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
