defmodule PortfolixirWeb.RefuseBeforeBindingTest do
  use PortfolixirWeb.ConnCase, async: true

  import ExUnit.CaptureLog, only: [with_log: 1]
  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures, only: [base_world: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Lifecycle.AccountNames
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.SecuritiesAccount

  defp german(conn), do: Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")

  defp open_depot_form(view) do
    view |> element("#add-account-button") |> render_click()
    view |> element("#account-form-dialog button[phx-value-mode='depot']") |> render_click()
  end

  defp submit_account(view, fields) do
    {_result, _log} =
      with_log(fn ->
        view
        |> form("#account-dialog-form", %{
          "account" =>
            Map.merge(
              %{"currency_code" => "EUR", "new_tag" => "", "cash_account_id" => ""},
              fields
            )
        })
        |> render_submit()
      end)

    :ok
  end

  defp text(view, selector) do
    view
    |> element(selector)
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.text()
    |> String.trim()
  end

  defp counts do
    {length(Portfolios.list_securities_accounts()), length(Portfolios.list_cash_accounts()),
     length(Buckets.list_buckets())}
  end

  # User story (security review 2026-10-12, K13):
  # As the operator creating an account or a tag,
  # I want a name the database cannot hold refused as a field error before
  # anything is looked up,
  # so that the page keeps my input and says why, instead of stopping.
  #
  # Acceptance criteria:
  # - The account dialog answers a depot name with a NUL under the name
  #   field, in the page's language, the field marked aria-invalid and tied
  #   to its error; nothing is written, not even the cash account.
  # - The dialog answers a new tag with a NUL in its alert, "New tag
  #   <message>.", in the page's language; nothing is written.
  # - The accounts page's inline tag answers it as a bucket error; nothing is
  #   written.
  # - The tag-bucket and account-name helpers run the text rule first: the
  #   pre-check names the refusal, the lookup answers no conflict, the
  #   find-or-create answers the changeset's field error.
  describe "the account dialog" do
    test "a depot name with a NUL is a field error, nothing written", %{conn: conn} do
      Process.flag(:trap_exit, true)
      base_world(depot_name: "Depot 1", cash_name: "Giro")
      before = counts()

      {:ok, view, _html} = live(conn, "/portfolios")
      open_depot_form(view)
      submit_account(view, %{"depot_name" => "Depot\u0000X", "cash_name" => "Neu"})

      assert Process.alive?(view.pid)
      assert counts() == before

      assert text(view, "#account-depot_name-error") ==
               "must not contain control characters or line breaks"

      assert has_element?(
               view,
               ~s{#account-dialog-form input[name="account[depot_name]"][aria-invalid="true"][aria-describedby="account-depot_name-error"]}
             )
    end

    test "the same field error reads in German", %{conn: conn} do
      Process.flag(:trap_exit, true)
      base_world(depot_name: "Depot 1", cash_name: "Giro")

      {:ok, view, _html} = live(german(conn), "/portfolios")
      open_depot_form(view)
      submit_account(view, %{"depot_name" => "Depot\u0000X", "cash_name" => "Neu"})

      assert text(view, "#account-depot_name-error") ==
               "darf keine Steuerzeichen und keine Zeilenumbrüche enthalten"
    end

    test "a new tag with a NUL is the dialog's alert, nothing written", %{conn: conn} do
      Process.flag(:trap_exit, true)
      base_world(depot_name: "Depot 1", cash_name: "Giro")
      before = counts()

      {:ok, view, _html} = live(conn, "/portfolios")
      open_depot_form(view)

      submit_account(view, %{
        "depot_name" => "Depot 2",
        "cash_name" => "Neu",
        "new_tag" => "Tag\u0000Y"
      })

      assert Process.alive?(view.pid)
      assert counts() == before

      assert text(view, "#account-form-dialog .alert-error") ==
               "New tag must not contain control characters or line breaks."
    end

    test "the tag alert reads in German", %{conn: conn} do
      Process.flag(:trap_exit, true)
      base_world(depot_name: "Depot 1", cash_name: "Giro")

      {:ok, view, _html} = live(german(conn), "/portfolios")
      open_depot_form(view)

      submit_account(view, %{
        "depot_name" => "Depot 2",
        "cash_name" => "Neu",
        "new_tag" => "Tag\u0000Y"
      })

      assert text(view, "#account-form-dialog .alert-error") ==
               "Neuer Tag darf keine Steuerzeichen und keine Zeilenumbrüche enthalten."
    end
  end

  test "the accounts page's inline tag with a NUL is a bucket error, nothing written",
       %{conn: conn} do
    Process.flag(:trap_exit, true)
    world = base_world(depot_name: "Depot 1", cash_name: "Giro")
    before = counts()

    {:ok, view, _html} = live(conn, "/portfolios")

    {_result, _log} =
      with_log(fn ->
        try do
          render_hook(view, "create_and_add_bucket", %{
            "owner" => "pair",
            "owner_id" => to_string(world.depot.id),
            "bucket_name" => "Tag\u0000Z"
          })
        catch
          :exit, _reason -> :crashed
        end
      end)

    assert Process.alive?(view.pid)
    assert counts() == before
    assert render(view) =~ "must not contain control characters or line breaks"
  end

  describe "the helpers refuse before binding" do
    test "the tag pre-check names the refusal" do
      assert {:error, {:text, :control_characters}} =
               Buckets.validate_tag_bucket_name("Tag\u0000")

      assert {:error, :name_too_long} =
               Buckets.validate_tag_bucket_name(String.duplicate("a", 101))
    end

    test "the find-or-create answers the changeset's field error" do
      before = length(Buckets.list_buckets())

      assert {:error, %Ecto.Changeset{errors: errors}} =
               Buckets.ensure_tag_bucket(Actor.owner_ui(), "Tag\u0000")

      assert Keyword.has_key?(errors, :name)
      assert length(Buckets.list_buckets()) == before
    end

    test "the account-name lookup answers no conflict for a name the text rule refuses" do
      world = base_world(depot_name: "Depot 1", cash_name: "Giro")

      assert AccountNames.conflict(SecuritiesAccount, world.portfolio.id, "Depot\u0000", nil) ==
               nil

      assert AccountNames.name_error(SecuritiesAccount, world.portfolio.id, "Depot\u0000") ==
               nil
    end
  end
end
