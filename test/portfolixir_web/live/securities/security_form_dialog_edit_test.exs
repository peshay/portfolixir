defmodule PortfolixirWeb.Securities.SecurityFormDialogEditTest do
  # User story:
  # As a local portfolio maintainer,
  # I want the security-form dialog to also work as an edit dialog so I can
  # adjust an existing entry from the row context menu without going through
  # the multi-step add flow.
  #
  # Acceptance criteria:
  # - When the dialog is rendered with an `:editing` assign carrying a
  #   Security, it mounts directly at the confirm step with the form fields
  #   prefilled.
  # - Submitting the form persists the change via `Catalog.update_security/2`
  #   and notifies the parent LiveView with `{:dialog, id, {:updated, sec}}`.
  # - Validation errors render inline; the dialog stays open and the form
  #   retains user input.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Repo
  alias PortfolixirWeb.Securities.SecurityFormDialog

  defp create_security! do
    {:ok, sec} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Arbolia Inc.",
        ticker_symbol: "ARBL",
        isin: "USEXMPL10014",
        currency_code: "USD",
        asset_class: "equity",
        provider: "manual"
      })

    sec
  end

  test "mounts at the confirm step with prefilled form when editing a security" do
    sec = create_security!()

    html =
      render_component(SecurityFormDialog,
        id: "security-form-dialog",
        editing: sec
      )

    # Confirm step shows the form, not the choose buttons
    assert html =~ ~s(name="security[name]")
    refute html =~ ~s(phx-value-mode="crypto")

    # Form is prefilled
    assert html =~ ~s(value="Arbolia Inc.")
    assert html =~ ~s(value="ARBL")
    assert html =~ ~s(value="USEXMPL10014")
  end

  test "renders the edit title when in edit mode" do
    sec = create_security!()

    html =
      render_component(SecurityFormDialog,
        id: "security-form-dialog",
        editing: sec
      )

    # Title should reflect that we are editing, not adding
    assert html =~ "Edit security" or html =~ "Wertpapier bearbeiten"
  end

  test "prefills inferred asset class for imported securities with blank stored asset_class" do
    {:ok, sec} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Placeholder",
        isin: "USEXMPL21490",
        currency_code: "USD",
        asset_class: "other",
        provider: "portfolio_performance"
      })

    {:ok, sec} =
      Catalog.update_security(Portfolixir.Actor.owner_ui(), sec, %{
        name: "Anleihe USA 21/47",
        asset_class: nil
      })

    html =
      render_component(SecurityFormDialog,
        id: "security-form-dialog",
        editing: sec
      )

    assert html =~ ~s(<option value="government_bond" selected)
  end

  test "saving updates the security via Catalog.update_security/2" do
    sec = create_security!()

    parent_pid = self()

    # We exercise the dialog as a stand-alone live component by wrapping it in
    # a host LiveView that forwards parent notifications back to the test.
    {:ok, view, _html} =
      live_isolated(build_conn(), PortfolixirWeb.Securities.DialogHostTest,
        session: %{"security_id" => sec.id, "test_pid" => :erlang.pid_to_list(parent_pid)}
      )

    view
    |> element("#security-form-dialog form")
    |> render_submit(%{
      "security" => %{
        "name" => "Arbolia",
        "ticker_symbol" => "ARBL",
        "isin" => "USEXMPL10014",
        "currency_code" => "USD",
        "exchange_code" => "NASDAQ",
        "asset_class" => "equity",
        "feed" => "",
        "feed_url" => "",
        "wkn" => "",
        "note" => "Edited via test"
      }
    })

    assert_receive {:updated_from_dialog, %Security{} = updated}
    assert updated.id == sec.id
    assert updated.exchange_code == "NASDAQ"
    assert updated.note == "Edited via test"

    reloaded = Repo.get!(Security, sec.id)
    assert reloaded.exchange_code == "NASDAQ"
  end

  # User story (#965):
  # As the operator giving a security an ISIN another security once carried,
  # I want the dialog to keep naming that security as it did, by its name
  # and its number,
  # so that keeping the agent's sentences free of stored names changes
  # nothing on my screen.
  #
  # Acceptance criteria:
  # - The refusal at the ISIN field reads, byte for byte, the sentence it read
  #   before #965; nothing is written.
  test "an ISIN another security once carried is refused in the words the dialog showed" do
    sec = create_security!()

    {:ok, renamed} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Kranich Werke",
        isin: "XS0000000025",
        currency_code: "EUR"
      })

    {:ok, _} = Catalog.record_isin_change(Portfolixir.Actor.owner_ui(), renamed, "XS0000000033")

    {:ok, view, _html} =
      live_isolated(build_conn(), PortfolixirWeb.Securities.DialogHostTest,
        session: %{"security_id" => sec.id, "test_pid" => :erlang.pid_to_list(self())}
      )

    html =
      view
      |> element("#security-form-dialog form")
      |> render_submit(%{
        "security" => %{
          "name" => "Arbolia Inc.",
          "ticker_symbol" => "ARBL",
          "isin" => "XS0000000025",
          "currency_code" => "USD",
          "asset_class" => "equity"
        }
      })

    errors =
      html
      |> Floki.parse_fragment!()
      |> Floki.find(".field-error")
      |> Enum.map(&Floki.text/1)

    assert (~s|is recorded as a former ISIN of "Kranich Werke" (security ##{renamed.id}); | <>
              "delete that alias or record an ISIN change instead") in errors

    assert Repo.get!(Security, sec.id).isin == "USEXMPL10014"
  end
end

defmodule PortfolixirWeb.Securities.DialogHostTest do
  @moduledoc false
  use Phoenix.LiveView

  alias Portfolixir.Catalog

  def mount(_params, %{"security_id" => security_id, "test_pid" => pid_charlist}, socket) do
    sec = Catalog.get_security(security_id)
    pid = :erlang.list_to_pid(pid_charlist)
    {:ok, socket |> assign(:editing, sec) |> assign(:test_pid, pid)}
  end

  def render(assigns) do
    ~H"""
    <.live_component
      module={PortfolixirWeb.Securities.SecurityFormDialog}
      id="security-form-dialog"
      editing={@editing}
    />
    """
  end

  def handle_info({:dialog, _id, {:updated, security}}, socket) do
    send(socket.assigns.test_pid, {:updated_from_dialog, security})
    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}
end
