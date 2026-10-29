defmodule Portfolixir.Input.DefaultIgnorableCharactersTest do
  # The text rule over Unicode's whole Default_Ignorable_Code_Point set
  # (security review 2026-10-12, H12): every character that renders as
  # nothing is refused by the writers, counted by the screen's marker,
  # spelled by the escape, dropped from a stored name and folded away by the
  # import's lookalike skeleton, not only the format characters the rule
  # first wrote out; a variation selector stands only after a base it can
  # vary. Every name, note and figure is synthetic. No network.
  #
  # async: false: the import applier's after-commit enrichment task needs the
  # shared sandbox connection (as in the project's own import tests).
  use PortfolixirWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures, only: [create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Classifications
  alias Portfolixir.Imports
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Imports.SecurityResolver
  alias Portfolixir.Input.Text
  alias Portfolixir.Portfolios
  alias Portfolixir.Repo

  # Default_Ignorable_Code_Point (Unicode DerivedCoreProperties.txt) beyond
  # the format characters the rule first wrote out; each range by its ends.
  @gap [
    # COMBINING GRAPHEME JOINER (Mn)
    0x034F,
    # HANGUL CHOSEONG / JUNGSEONG FILLER (Lo)
    0x115F,
    0x1160,
    # KHMER VOWEL INHERENT AQ / AA (Mn)
    0x17B4,
    0x17B5,
    # MONGOLIAN FREE VARIATION SELECTOR ONE..THREE, FOUR (Mn)
    0x180B,
    0x180C,
    0x180D,
    0x180F,
    # HANGUL FILLER, HALFWIDTH HANGUL FILLER (Lo)
    0x3164,
    0xFFA0,
    # reserved default-ignorables (Cn)
    0xFFF0,
    0xFFF8,
    0xE0080,
    0xE00FF,
    0xE01F0,
    0xE0FFF
  ]

  defp c(code_point), do: <<code_point::utf8>>

  defp hex(code_point),
    do: "U+" <> (code_point |> Integer.to_string(16) |> String.pad_leading(4, "0"))

  # Every code point outside printable ASCII spelled out, for the messages.
  defp visible(nil), do: "nil"

  defp visible(text) when is_binary(text) do
    for <<code_point::utf8 <- text>>, into: "" do
      if code_point in 0x20..0x7E, do: <<code_point>>, else: "[" <> hex(code_point) <> "]"
    end
  end

  # The variation-selector byte encoding: bytes 0-15 as VS1-VS16, 16-255 as
  # VS17-VS256 (U+E0100-U+E01EF).
  defp vs_byte(byte) when byte < 16, do: c(0xFE00 + byte)
  defp vs_byte(byte), do: c(0xE0100 + byte - 16)

  defp vs_decode(text) do
    for <<code_point::utf8 <- text>>, into: "" do
      cond do
        code_point in 0xFE00..0xFE0F -> <<code_point - 0xFE00>>
        code_point in 0xE0100..0xE01EF -> <<code_point - 0xE0100 + 16>>
        true -> ""
      end
    end
  end

  # One selector after each visible letter, so never a run of two.
  defp interleave(visible_text, hidden) do
    {parts, _left} =
      visible_text
      |> String.graphemes()
      |> Enum.map_reduce(:binary.bin_to_list(hidden), fn
        " ", left -> {" ", left}
        letter, [byte | rest] -> {letter <> vs_byte(byte), rest}
        letter, [] -> {letter, []}
      end)

    Enum.join(parts)
  end

  defp api(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  # User story (security review 2026-10-12, H12):
  # As the operator whose agent reads what I reviewed,
  # I want every character that renders as nothing refused, counted and
  # spelled by the one text rule, a lone variation selector included where
  # it has no base to vary,
  # so that no text carries a payload I cannot see.
  #
  # Acceptance criteria:
  # - Each default-ignorable code point appended to a name fails check/2,
  #   counts as invisible and is spelled by escape_invisible/1.
  # - Variation selectors interleaved one per Latin letter are refused.
  describe "the one text rule" do
    test "refuses, counts and spells every default-ignorable character" do
      # Controls: the written-out set holds.
      assert Text.check("Synthetic" <> c(0x200B) <> " Fund", max: 255) ==
               {:error, :invisible_characters}

      assert Text.escape_invisible("Fund" <> c(0xE0041)) == "Fund[U+E0041]"

      observed =
        for code_point <- @gap do
          text = "Synthetic Fund" <> c(code_point)

          {hex(code_point),
           %{
             check: Text.check(text, max: 255),
             count: Text.invisible_count(text),
             escaped: Text.escape_invisible(text) != text
           }}
        end

      leaks =
        for {name, %{check: :ok}} <- observed, do: name

      assert leaks == [],
             "pass Text.check/2 (writer rule), count 0 (screen marker) and stay unspelled: " <>
               inspect(observed, limit: :infinity)
    end

    test "refuses single variation selectors interleaved one per letter" do
      text = interleave("Note on fund", "HIDDEN")

      # Renders as the twelve visible letters, carries six hidden bytes, and
      # never holds a run of two selectors.
      assert String.length(text) == 12
      assert Text.codepoint_length(text) == 18
      assert vs_decode(text) == "HIDDEN"

      assert Text.check(text, multiline: true, max: Text.entry_body_max()) ==
               {:error, :invisible_characters},
             "accepted #{visible(text)} (decodes to #{inspect(vs_decode(text))})"
    end
  end

  # User story (security review 2026-10-12, H12):
  # As the operator reviewing what an agent wrote over the API,
  # I want a research-log body carrying a default-ignorable character
  # refused, and a security name stored without it,
  # so that nothing stored hides text from me.
  #
  # Acceptance criteria:
  # - A note body carrying U+034F, or selectors interleaved one per letter,
  #   answers 422.
  # - A security name carrying U+034F answers 422 or is stored without it.
  describe "API writers" do
    setup %{conn: conn} do
      %{conn: api(conn), security: create_security!(name: "Coastal Ferry Lines", ticker: "CFL")}
    end

    test "POST /api/v1/securities/:id/notes refuses a body carrying U+034F",
         %{conn: conn, security: security} do
      body = "Fleet renewal on plan." <> c(0x034F)

      response =
        post(
          conn,
          "/api/v1/securities/#{security.id}/notes",
          Jason.encode!(%{
            "note" => %{
              "kind" => "evidence",
              "body" => body,
              "source_quality" => "primary",
              "as_of" => "2026-01-02"
            }
          })
        )

      stored =
        if response.status == 201, do: Jason.decode!(response.resp_body)["data"]["body"]

      assert response.status == 422,
             "answered #{response.status}, stored body #{visible(stored)}"
    end

    test "POST /api/v1/securities/:id/notes refuses a body smuggling bytes in interleaved selectors",
         %{conn: conn, security: security} do
      body = interleave("Note on fund", "HIDDEN")

      response =
        post(
          conn,
          "/api/v1/securities/#{security.id}/notes",
          Jason.encode!(%{
            "note" => %{
              "kind" => "evidence",
              "body" => body,
              "source_quality" => "primary",
              "as_of" => "2026-01-02"
            }
          })
        )

      read_back =
        if response.status == 201 do
          conn
          |> get("/api/v1/securities/#{security.id}/notes")
          |> json_response(200)
          |> get_in(["data", "entries"])
          |> inspect_notes()
        end

      assert response.status == 422,
             "answered #{response.status}; GET answers #{inspect(read_back)}"
    end

    test "POST /api/v1/securities refuses U+034F in a name or stores the name without it",
         %{conn: conn} do
      response =
        post(
          conn,
          "/api/v1/securities",
          Jason.encode!(%{security: %{name: "Harbour Cranes" <> c(0x034F), currency_code: "EUR"}})
        )

      stored =
        if response.status == 201, do: Jason.decode!(response.resp_body)["data"]["name"]

      # Control (G23 pin): a format character is stripped from a name.
      control =
        conn
        |> post(
          "/api/v1/securities",
          Jason.encode!(%{
            security: %{name: "Harbour" <> c(0x200B) <> " Lifts", currency_code: "EUR"}
          })
        )
        |> json_response(201)

      assert control["data"]["name"] == "Harbour Lifts"

      assert response.status == 422 or stored == "Harbour Cranes",
             "answered #{response.status}, stored name #{visible(stored)}"
    end
  end

  defp inspect_notes(notes) when is_list(notes) do
    Enum.map(notes, fn note ->
      %{body: visible(note["body"]), hidden_payload: vs_decode(note["body"])}
    end)
  end

  defp inspect_notes(other), do: other

  # User story (security review 2026-10-12, H12):
  # As the operator reading a row stored before the rule,
  # I want the invisible-text note wherever such a row carries any
  # default-ignorable character,
  # so that I know the text holds something I cannot see.
  #
  # Acceptance criteria:
  # - The note renders for each default-ignorable code point.
  describe "the screen's marker" do
    test "a stored text carrying a default-ignorable character gets the invisible-text note" do
      control =
        render_component(&PortfolixirWeb.AppShell.invisible_text_note/1,
          texts: ["Fleet" <> c(0x200B)]
        )

      assert control =~ "invisible-text-note"

      unmarked =
        for code_point <- @gap,
            html =
              render_component(&PortfolixirWeb.AppShell.invisible_text_note/1,
                texts: ["Fleet renewal on plan." <> c(code_point)]
              ),
            not (html =~ "invisible-text-note"),
            do: hex(code_point)

      assert unmarked == [], "no marker rendered for: #{Enum.join(unmarked, ", ")}"
    end
  end

  # User story (security review 2026-10-12, H12):
  # As the operator importing a file that names my configured security,
  # I want a name that differs from it only by a default-ignorable
  # character to be read as that security,
  # so that an import never books onto a twin I cannot tell apart.
  #
  # Acceptance criteria:
  # - skeleton/1 of a name with any default-ignorable character equals the
  #   bare name's; a Hangul filler folds to the space it renders as.
  # - A CSV row naming the U+034F twin matches or is flagged, and no second
  #   security is created.
  describe "the import's lookalike guard" do
    defp configured!(name) do
      {:ok, security} =
        Catalog.create_security(Actor.owner_ui(), %{name: name, currency_code: "EUR"})

      {:ok, classification} =
        Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy H12"})

      {:ok, category} =
        Classifications.create_category(Actor.owner_ui(), %{
          classification_id: classification.id,
          name: "Core"
        })

      {:ok, _} =
        Classifications.assign_security(
          Actor.owner_ui(),
          security.id,
          classification.id,
          category.id
        )

      security
    end

    test "skeleton/1 folds every default-ignorable character away, as it does a format character" do
      base = SecurityResolver.skeleton("Config AG")

      # Control (G23 pin): a format character is folded away.
      assert SecurityResolver.skeleton("Config AG" <> c(0x200B)) == base

      differing =
        for code_point <- @gap,
            SecurityResolver.skeleton("Config AG" <> c(code_point)) != base,
            do: hex(code_point)

      assert differing == [],
             "skeleton differs from the bare name's for: #{Enum.join(differing, ", ")}"

      # A Hangul filler renders as a blank: it folds to the space it shows.
      assert SecurityResolver.skeleton("Config" <> c(0x3164) <> "AG") == base
    end

    test "a CSV row naming a U+034F twin of a configured security is flagged, not silently created" do
      configured = configured!("Config AG")

      csv = """
      Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle
      2024-03-01 00:00:00;Einlage;;;;1.100,00;;;1.100,00;Test-Cash;;;
      2024-03-04 10:01:00;Kauf;Config#{c(0x200B)} AG;10;10,00;100,00;;;100,00;Test-Depot;Test-Cash;;
      2024-03-05 10:01:00;Kauf;Config AG#{c(0x034F)};10;10,00;100,00;;;100,00;Test-Depot;Test-Cash;;
      """

      {:ok, preview} = PortfolioPerformance.parse(csv, filename: "h12.csv")
      %{resolutions: resolutions} = Imports.resolve_securities(preview)

      by_name = Map.new(resolutions, fn row -> {row.ref.name, row} end)

      # Control (G23 pin): the zero-width-space twin matches the configured
      # security at the name tier (the name strip drops U+200B).
      control = by_name["Config AG"]
      assert control.status == :matched
      assert control.matched.security_id == configured.id

      twin = by_name["Config AG" <> c(0x034F)]

      {:ok, portfolio} =
        Portfolios.create_portfolio(Actor.owner_ui(), %{
          name: "H12 target",
          base_currency_code: "EUR"
        })

      {applied, _log} =
        with_log(fn -> Imports.apply(preview, %{portfolio_id: portfolio.id}) end)

      lookalikes =
        Security
        |> Repo.all()
        |> Enum.filter(&(SecurityResolver.skeleton(&1.name) |> String.starts_with?("config ag")))
        |> Enum.map(&visible(&1.name))

      observed = %{
        row_errors: preview.errors,
        twin_status: twin && twin.status,
        twin_at_risk: twin && Map.get(twin, :at_risk),
        created_securities: match?({:ok, _}, applied) && elem(applied, 1).created_securities,
        catalog_lookalikes: lookalikes
      }

      # The twin is read as the configured security: its own reference
      # matches or is flagged, or its name folds into the configured one's
      # reference, so no resolution creates a security.
      assert preview.errors != [] or
               (is_nil(twin) and Enum.all?(resolutions, &(&1.status != :create))) or
               (twin && twin.status in [:matched, :config_at_risk]),
             "the U+034F twin resolves silently: #{inspect(observed)}"

      assert observed.created_securities in [false, 0],
             "the import created a security: #{inspect(observed)}"

      assert length(lookalikes) == 1,
             "a visually identical twin was created: #{inspect(observed)}"
    end
  end
end
