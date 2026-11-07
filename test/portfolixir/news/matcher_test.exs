defmodule Portfolixir.News.MatcherTest do
  # ADR-0056 §2 (Sprint 27, N4): the alias matcher. An aggregator item's
  # title is split into sentences, each sentence into words, and the words
  # are looked up in a table built from the universe's aliases, ISINs and
  # WKNs — no pattern from input, no backtracking. Pure: no database.
  # Synthetic names only.
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Portfolixir.News.Matcher

  defp alias_(token, opts \\ []),
    do: %{
      token: token,
      context: Keyword.get(opts, :context, []),
      case: Keyword.get(opts, :case, :insensitive)
    }

  defp entry(id, aliases, opts \\ []),
    do: %{
      id: id,
      aliases: aliases,
      isin: Keyword.get(opts, :isin),
      wkn: Keyword.get(opts, :wkn)
    }

  defp universe,
    do: [
      entry(1, [alias_("Northwind Harbour"), alias_("NWH", case: :sensitive)],
        isin: "DE000NWH0001",
        wkn: "NWH000"
      ),
      entry(2, [alias_("Larkspur Robotics"), alias_("Larkspur")]),
      # A ticker that is also an English word: only beside a context word.
      entry(3, [alias_("BOLT", case: :sensitive, context: ~w(stock shares Boltwork))]),
      entry(4, [alias_("Larkspur Robotics")])
    ]

  # User story:
  # As the operator's agent reading a news digest,
  # I want an aggregator item to land on the one security its title names,
  # to stay unassigned when it names none, and to list the candidates when it
  # names several,
  # so that no item is guessed onto a security and none is silently lost.
  #
  # Acceptance criteria:
  # - One hit assigns, none leaves it unassigned, several make it ambiguous
  #   with the candidates sorted.
  # - A multi-word alias matches as a run of words, across any whitespace.
  # - ISIN and WKN match as literal words.
  describe "one, none and several" do
    test "one security named gives that security" do
      assert Matcher.match("Northwind Harbour raises its dividend", universe()) ==
               {:assigned, 1}
    end

    test "no security named leaves the item unassigned" do
      assert Matcher.match("Markets drift ahead of the holiday", universe()) == :unassigned
    end

    test "several securities named make it ambiguous, the candidates sorted" do
      assert Matcher.match("Northwind Harbour and Larkspur agree a deal", universe()) ==
               {:ambiguous, [1, 2]}

      # One alias held by two securities is ambiguous too.
      assert Matcher.match("Larkspur Robotics opens a plant", universe()) ==
               {:ambiguous, [2, 4]}
    end

    test "a multi-word alias is a run of words, whatever the whitespace" do
      assert Matcher.match("Northwind  \t Harbour expands", universe()) == {:assigned, 1}
      assert Matcher.match("Northwind expands its Harbour", universe()) == :unassigned
    end

    test "ISIN and WKN match as literal words" do
      assert Matcher.match("Filing for DE000NWH0001 published", universe()) == {:assigned, 1}
      assert Matcher.match("WKN NWH000: new prospectus", universe()) == {:assigned, 1}
      assert Matcher.match("XDE000NWH0001 is another code", universe()) == :unassigned
    end

    test "an empty universe or an empty title matches nothing" do
      assert Matcher.match("Northwind Harbour", []) == :unassigned
      assert Matcher.match("", universe()) == :unassigned
    end

    test "outcome/1 names the three outcomes" do
      assert Matcher.outcome([]) == :unassigned
      assert Matcher.outcome([7]) == {:assigned, 7}
      assert Matcher.outcome([9, 7, 9]) == {:ambiguous, [7, 9]}
    end
  end

  # User story:
  # As the operator who aliased a ticker that is also an English word,
  # I want it matched only beside one of the words I listed, in the same
  # sentence,
  # so that every headline with the word "bolt" in it does not land on the
  # security.
  #
  # Acceptance criteria:
  # - Without a context word in the sentence, no match.
  # - A context word in another sentence does not count.
  # - A context word matches whatever its case; the token keeps its own.
  describe "context" do
    test "a ticker that is an English word matches only beside a context word" do
      assert Matcher.match("A BOLT from the blue for markets", universe()) == :unassigned
      assert Matcher.match("BOLT stock jumps after results", universe()) == {:assigned, 3}
      assert Matcher.match("Shares of BOLT slide", universe()) == {:assigned, 3}
      assert Matcher.match("Boltwork's BOLT rallies", universe()) == {:assigned, 3}
    end

    test "the context word must be in the same sentence" do
      assert Matcher.match("Stock markets rise. BOLT from the blue.", universe()) ==
               :unassigned

      assert Matcher.match("Markets rise! BOLT shares climb?", universe()) == {:assigned, 3}
    end

    test "a context word is a whole word, not part of one" do
      assert Matcher.match("BOLT stockpiles grow", universe()) == :unassigned
    end
  end

  # User story:
  # As the operator who said whether an alias's case matters,
  # I want a sensitive alias matched only as written and an insensitive one
  # in any case,
  # so that a short ticker does not match an ordinary lower-case word.
  #
  # Acceptance criteria:
  # - `sensitive` matches only the exact case; `insensitive` any case,
  #   including non-ASCII letters.
  describe "case" do
    test "a sensitive alias matches only as written" do
      assert Matcher.match("NWH lifts guidance", universe()) == {:assigned, 1}
      assert Matcher.match("nwh lifts guidance", universe()) == :unassigned
      assert Matcher.match("Nwh lifts guidance", universe()) == :unassigned
    end

    test "an insensitive alias matches in any case" do
      assert Matcher.match("NORTHWIND HARBOUR LIFTS GUIDANCE", universe()) == {:assigned, 1}
      assert Matcher.match("northwind harbour lifts guidance", universe()) == {:assigned, 1}
    end

    test "case folding covers letters beyond ASCII" do
      universe = [entry(5, [alias_("Ölmühle Süd")])]
      assert Matcher.match("ÖLMÜHLE SÜD erhöht die Prognose", universe) == {:assigned, 5}
      assert Matcher.match("ölmühle süd senkt die Prognose", universe) == {:assigned, 5}
    end
  end

  # User story:
  # As the operator's agent,
  # I want an alias found wherever a word boundary is, and nowhere else,
  # so that "Larkspur" matches "Larkspur's" and "(Larkspur)" but not
  # "Larkspurs" or "SuperLarkspur".
  #
  # Acceptance criteria:
  # - Sentence start and end, punctuation on either side, a possessive, a
  #   hyphen and quotes are boundaries.
  # - A letter, a digit or an underscore joined to the token is not.
  # - An abbreviation's dot ("Corp.", "Inc.", an initial) does not end the
  #   sentence; a dot inside a token ("BRK.B") is part of it.
  # - An invisible format character inside a word does not split it.
  describe "word boundaries" do
    test "sentence starts and ends and punctuation are boundaries" do
      for title <- [
            "Larkspur",
            "Larkspur.",
            "Larkspur gains",
            "Gains for Larkspur",
            "Gains for Larkspur!",
            "Larkspur's plant",
            "(Larkspur) gains",
            "\"Larkspur\" gains",
            "Larkspur-led consortium",
            "Gains: Larkspur, others",
            "«Larkspur» gewinnt",
            "Gains for Larkspur\nOther news"
          ] do
        assert Matcher.match(title, universe()) == {:assigned, 2}, title
      end
    end

    test "a token joined to a letter, a digit or an underscore is not matched" do
      for title <- ["Larkspurs gain", "SuperLarkspur gains", "Larkspur2 gains", "Larkspur_x"] do
        assert Matcher.match(title, universe()) == :unassigned, title
      end
    end

    test "a non-ASCII letter joined to the token is part of the word" do
      assert Matcher.match("Larkspuré gains", universe()) == :unassigned
      assert Matcher.match("éLarkspur gains", universe()) == :unassigned
    end

    test "an abbreviation's dot does not end the sentence" do
      universe = [entry(6, [alias_("BRK.B", case: :sensitive, context: ~w(shares))])]
      assert Matcher.match("BRK.B shares rise", universe) == {:assigned, 6}
      assert Matcher.match("BRK B shares rise", universe) == :unassigned

      universe = [entry(7, [alias_("ACME", case: :sensitive, context: ~w(shares))])]
      assert Matcher.match("ACME Corp. shares rise", universe) == {:assigned, 7}
      assert Matcher.match("ACME Inc. Shares rise", universe) == {:assigned, 7}
      assert Matcher.match("J. ACME shares", universe) == {:assigned, 7}
      assert Matcher.match("ACME rises. Shares of others fall", universe) == :unassigned
    end

    test "an invisible format character inside a word does not split it" do
      # U+200B ZERO WIDTH SPACE and U+00AD SOFT HYPHEN, written as escapes.
      assert Matcher.match("Lark\u200Bspur gains", universe()) == {:assigned, 2}
      assert Matcher.match("Lark\u00ADspur gains", universe()) == {:assigned, 2}
    end

    test "a non-breaking or other Unicode space separates words" do
      assert Matcher.match("Northwind\u00A0Harbour gains", universe()) == {:assigned, 1}
      assert Matcher.match("Northwind\u2009Harbour gains", universe()) == {:assigned, 1}
    end
  end

  # User story:
  # As the operator whose server reads text from hosts it does not control,
  # I want the matcher's work to grow with the text and not with what the
  # text repeats,
  # so that a hostile feed cannot stall the matching of everyone's news.
  #
  # Acceptance criteria:
  # - A megabyte of one repeated letter, and a megabyte of one repeated
  #   word, against thousands of aliases, finish well within a bound a
  #   quadratic walk could never meet.
  # - Over any string, the matcher never raises.
  # A megabyte takes about two seconds here on the slowest shape. A walk
  # quadratic in the text would take about 10^12 steps, hours; so any bound
  # in seconds separates the two, and a generous one keeps a slow CI runner
  # from failing a linear matcher.
  @linear_bound_micros 15_000_000

  describe "hostile input" do
    setup do
      aliases =
        for n <- 1..3_000 do
          entry(n, [
            alias_("Synthetic Issuer #{n}"),
            alias_("a", context: ["word#{n}"]),
            alias_("a a a a a a a a #{n}")
          ])
        end

      %{universe: Matcher.compile(aliases)}
    end

    test "a megabyte of one repeated letter stays linear", %{universe: universe} do
      text = String.duplicate("a", 1_000_000)
      {micros, outcome} = :timer.tc(fn -> Matcher.match(text, universe) end)
      assert outcome == :unassigned
      assert micros < @linear_bound_micros
    end

    test "a megabyte of one repeated word stays linear", %{universe: universe} do
      text = String.duplicate("a ", 500_000)
      {micros, outcome} = :timer.tc(fn -> Matcher.match(text, universe) end)
      assert outcome == :unassigned
      assert micros < @linear_bound_micros
    end

    test "a megabyte of sentences stays linear", %{universe: universe} do
      text = String.duplicate("a. ", 333_333)
      {micros, outcome} = :timer.tc(fn -> Matcher.match(text, universe) end)
      assert outcome == :unassigned
      assert micros < @linear_bound_micros
    end

    property "the matcher never raises, and its outcome is one of three shapes" do
      universe = Matcher.compile(universe())

      check all(
              text <-
                one_of([
                  string(:printable, max_length: 300),
                  string(:utf8, max_length: 300),
                  binary(max_length: 300)
                ]),
              max_runs: 300
            ) do
        case Matcher.match(text, universe) do
          :unassigned -> :ok
          {:assigned, id} when is_integer(id) -> :ok
          {:ambiguous, [_, _ | _] = ids} -> assert ids == Enum.sort(Enum.uniq(ids))
        end
      end
    end

    property "an alias of words set between line breaks is always found" do
      check all(
              words <- list_of(string(:alphanumeric, min_length: 1, max_length: 12), length: 1..3),
              before <- string(:printable, max_length: 80),
              after_ <- string(:printable, max_length: 80),
              max_runs: 200
            ) do
        token = Enum.join(words, " ")
        universe = [entry(42, [alias_(token, case: :sensitive)])]
        text = before <> "\n" <> token <> " \n" <> after_

        assert 42 in Matcher.matches(text, universe)
      end
    end

    property "aliases built from any text never make the matcher raise" do
      check all(
              tokens <- list_of(string(:utf8, min_length: 1, max_length: 20), max_length: 10),
              text <- string(:utf8, max_length: 200),
              max_runs: 200
            ) do
        universe =
          tokens
          |> Enum.with_index(1)
          |> Enum.map(fn {token, id} ->
            entry(id, [alias_(token, context: [token]), alias_(token, case: :sensitive)])
          end)

        assert Matcher.match(text, universe) == Matcher.outcome(Matcher.matches(text, universe))
      end
    end
  end
end
