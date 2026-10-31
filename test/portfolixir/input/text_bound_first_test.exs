defmodule Portfolixir.Input.TextBoundFirstTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Input.Text

  # The rule as it answered before the bound moved first: encoding, control
  # characters, invisible characters, then the length counted over a list of
  # code points. The reference the corpus below is held to.
  @controls ~r/[\x{0000}-\x{0008}\x{000B}\x{000C}\x{000E}-\x{001F}\x{007F}-\x{009F}]/u
  @single_line_controls ~r/[\x{0000}-\x{001F}\x{007F}-\x{009F}]/u
  defp reference(value, opts) do
    cond do
      not String.valid?(value) ->
        {:error, :invalid_encoding}

      Regex.match?(if(opts[:multiline], do: @controls, else: @single_line_controls), value) ->
        {:error, :control_characters}

      Text.invisible_count(value) > 0 ->
        {:error, :invisible_characters}

      opts[:max] && length(String.codepoints(value)) > opts[:max] ->
        {:error, :too_long}

      true ->
        :ok
    end
  end

  @corpus [
    "",
    "Café Growth ETF",
    "a\u0000b",
    "a\u0007b",
    "a\nb",
    "a\tb",
    "line one\nline two\r\n\tindented",
    "a\u007Fb",
    "a\u0085b",
    <<0xFF>>,
    <<"ab", 0xFE, "cd">>,
    "Zero\u200Bwidth",
    "\u202Eright to left",
    "e\u0301\u0301\u0301",
    "👨\u200D👩\u200D👧",
    "❤\uFE0F",
    "a\uFE0F\uFE0F",
    "𝔘𝔫𝔦𝔠𝔬𝔡𝔢",
    String.duplicate("é", 5),
    String.duplicate("é", 6),
    String.duplicate("𝔘", 5),
    String.duplicate("𝔘", 6),
    String.duplicate("a", 255),
    String.duplicate("a", 256),
    String.duplicate("€", 255),
    String.duplicate("€", 256)
  ]

  @option_sets [[], [max: 5], [max: 255], [multiline: true], [multiline: true, max: 5]]

  # User story (security review 2026-10-12, H55):
  # As the operator or agent sending text to any writer,
  # I want an over-long value refused by its size before it is scanned,
  # so that one large field costs a bounded amount of work and memory.
  #
  # Acceptance criteria:
  # - A value far past its bound is refused as too long within a small heap
  #   and a short time.
  # - The code-point count needs no list, and counts as it counted.
  # - For the existing fixture set the rule answers as it answered; only a
  #   value that is both too long and refused otherwise now names its length.
  test "a value far past its bound is refused as too long within a small heap" do
    plain = String.duplicate("a", 8_000_000)
    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        Process.flag(:max_heap_size, %{size: 2_000_000, kill: true, error_logger: false})

        send(
          parent,
          {:answers,
           [
             Text.check(plain, max: 255),
             Text.check(plain <> "\u0000", max: 255),
             Text.check(plain, multiline: true, max: 7_000_000)
           ]}
        )
      end)

    assert_receive {:DOWN, ^ref, :process, ^pid, reason}, 5_000
    assert reason == :normal, "the check was killed: #{inspect(reason)}"
    assert_received {:answers, answers}
    assert answers == List.duplicate({:error, :too_long}, 3)
  end

  test "the code-point count needs no list and counts as before" do
    for value <- @corpus ++ [<<0xC3>>, <<"a", 0xF0, 0x9F>>] do
      assert Text.codepoint_length(value) == length(String.codepoints(value)), inspect(value)
    end

    value = String.duplicate("€", 3_000_000)
    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        Process.flag(:max_heap_size, %{size: 2_000_000, kill: true, error_logger: false})
        send(parent, {:count, Text.codepoint_length(value)})
      end)

    assert_receive {:DOWN, ^ref, :process, ^pid, reason}, 5_000
    assert reason == :normal, "the count was killed: #{inspect(reason)}"
    assert_received {:count, 3_000_000}
  end

  test "the answers are unchanged for the fixture set" do
    for value <- @corpus, opts <- @option_sets do
      expected =
        case reference(value, opts) do
          {:error, _other} = refused ->
            if (String.valid?(value) and opts[:max]) &&
                 length(String.codepoints(value)) > opts[:max],
               do: {:error, :too_long},
               else: refused

          answer ->
            answer
        end

      assert Text.check(value, opts) == expected, "#{inspect(value)} #{inspect(opts)}"
    end
  end
end
