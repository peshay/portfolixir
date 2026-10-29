defmodule PortfolixirWeb.TaxStatementFieldErrorsTest do
  use PortfolixirWeb.ConnCase, async: true

  import ExUnit.CaptureLog, only: [with_log: 1]
  import Phoenix.LiveViewTest

  alias Portfolixir.Tax
  alias Portfolixir.Tax.StatementSnapshot
  alias PortfolixirWeb.TaxLive

  defp german(conn), do: Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")

  defp submit(view, holder) do
    view
    |> form("#tax-statement-form", %{
      "statement" => %{
        "holder" => holder,
        "institution" => "Example Bank",
        "as_of" => "2025-12-31",
        "taxable_income" => "100.00"
      }
    })
    |> render_submit()
  end

  # The note's message, after its severity word.
  defp note_text(view) do
    view
    |> element("#tax-form-error")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.text()
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> List.last()
  end

  # User story (security review 2026-10-12, H36):
  # As the operator recording a tax statement,
  # I want a taxpayer name the database cannot hold answered on the form,
  # so that my input stays and the problem note names the field in words,
  # instead of the page stopping.
  #
  # Acceptance criteria:
  # - A holder with a NUL keeps the page alive, stores nothing, and the
  #   problem note reads "<label>: <message>" in the page's language, the
  #   label being the holder field's own ("Taxpayer").
  # - The holder field carries aria-invalid and points at the note.
  # - Every field the statement form can be refused on reads under a label,
  #   never its raw key.
  test "a holder with a NUL is a field error on the form, in English", %{conn: conn} do
    Process.flag(:trap_exit, true)
    {:ok, view, _html} = live(conn, "/tax?holder=Owner&year=2025")

    {_result, _log} = with_log(fn -> submit(view, "Guest\u0000") end)

    assert Process.alive?(view.pid)
    assert Tax.list_snapshots(tax_year: 2025) == []

    assert note_text(view) == "Taxpayer: must not contain control characters or line breaks"

    assert has_element?(
             view,
             ~s{#tax-statement-form input[name="statement[holder]"][aria-invalid="true"][aria-describedby="tax-form-error"]}
           )
  end

  test "the same refusal reads in German", %{conn: conn} do
    Process.flag(:trap_exit, true)
    {:ok, view, _html} = live(german(conn), "/tax?holder=Owner&year=2025")

    {_result, _log} = with_log(fn -> submit(view, "Guest\u0000") end)

    assert note_text(view) ==
             "Steuerpflichtige Person: darf keine Steuerzeichen und keine Zeilenumbrüche enthalten"
  end

  test "every field the statement form can be refused on has a label, not its raw key" do
    fields =
      [:institution, :holder, :tax_year, :as_of, :church_tax_rate, :note] ++
        StatementSnapshot.money_fields()

    raw = for field <- fields, TaxLive.form_error_label(field) == to_string(field), do: field
    assert raw == []
  end
end
