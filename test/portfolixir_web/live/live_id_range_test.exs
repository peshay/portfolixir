defmodule PortfolixirWeb.LiveIdRangeTest do
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @past_bigint "99999999999999999999999"

  @live_routes ~w(/ /portfolio /securities /portfolios /transactions /cashflow /snapshots /tax
                  /risk /imports /buckets /classifications)

  @id_keys ~w(id security_id classification_id category_id transaction_id view_id view
              security_ids)

  # User story (#855, the #840 guarantee extended to the pages):
  # As the operator following a link with a mangled id,
  # I want the page to open without it rather than answer a server error,
  # so that a bad URL costs me nothing but the id.
  #
  # Acceptance criteria:
  # - On every live route, an id-shaped query parameter past the bigint range
  #   is dropped by a redirect to the same page without it — never an HTTP
  #   500 on the static render or a crash on the connected one.
  # - A path id past the range (`/securities/:id`, `/classifications/:id`)
  #   redirects to the route's index.
  # - An in-range id and a malformed one keep the answer they had.
  test "an id past the bigint range never reaches the database from a page", %{conn: conn} do
    for path <- @live_routes, key <- @id_keys do
      url = "#{path}?#{key}=#{@past_bigint}"

      case live(conn, url) do
        {:ok, _view, _html} ->
          flunk("#{url} rendered with the out-of-range id instead of dropping it")

        {:error, {kind, %{to: to}}} when kind in [:redirect, :live_redirect] ->
          refute to =~ @past_bigint, "#{url} redirected with the id still in it: #{to}"
          assert URI.parse(to).path == path
      end
    end

    for path <- ["/securities/#{@past_bigint}", "/classifications/#{@past_bigint}"] do
      assert {:error, {kind, %{to: to}}} = live(conn, path)
      assert kind in [:redirect, :live_redirect]
      assert to in ["/securities", "/classifications"]
    end

    # The static render too: an HTTP 302, never a 500.
    conn = get(conn, "/securities?id=#{@past_bigint}")
    assert redirected_to(conn, 302) == "/securities"

    # An in-range unknown id keeps its old answer (the page renders).
    assert {:ok, _view, _html} = live(build_conn(), "/securities?id=999999")
  end
end
