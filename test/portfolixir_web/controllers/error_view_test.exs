defmodule PortfolixirWeb.ErrorViewTest do
  # Not async: the oversized-body requests allocate a few megabytes each.
  use PortfolixirWeb.ConnCase, async: false

  alias PortfolixirWeb.ErrorView

  # One byte past the endpoint's body bound (Plug.Parsers length: 8_000_000).
  @too_large 8_000_001

  # User story (E25 S2, F68; design pass Part 11 item 4, board 11):
  # As an operator whose browser meets an error the app answers,
  # I want an error page for every status, with its number and a status line
  # in my language,
  # so that a refused request reads as refused rather than as a bodyless
  # server error, and the reason is not lost on the way.
  #
  # Acceptance criteria:
  # - A 400, 403, 406 and 413 in the browser answer with that status and a body
  #   of the form "403 · Forbidden", not a bodyless 500.
  # - 404 and 500 take the same clause, so they carry their number too.
  # - The status line follows the page's language: the locale the pipeline
  #   chose, else the locale cookie, then the browser's language, then English.
  # - The error that reaches the server is the original one, which carries
  #   nothing from the request, never a rendering crash holding the request.
  describe "the browser's error pages" do
    test "a form posted without its CSRF token answers 403 with a status line", %{conn: conn} do
      password = "error-page-" <> Integer.to_string(System.unique_integer([:positive]))

      {403, _headers, body} =
        assert_error_sent(403, fn ->
          post(with_csrf(conn), "/login", %{"password" => password})
        end)

      assert body == "403 · Forbidden"
      refute body =~ password

      # What the adapter logs is the original error, and its message holds
      # nothing the request carried.
      error =
        assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
          post(with_csrf(conn), "/login", %{"password" => password})
        end

      refute Exception.message(error) =~ password
    end

    test "an unreadable body answers 400", %{conn: conn} do
      {400, _headers, body} =
        assert_error_sent(400, fn ->
          conn
          |> put_req_header("accept", "text/html")
          |> put_req_header("content-type", "application/json")
          |> post("/login", "{")
        end)

      assert body == "400 · Bad Request"
    end

    test "a format the address does not serve answers 406", %{conn: conn} do
      {406, _headers, body} =
        assert_error_sent(406, fn ->
          conn |> put_req_header("accept", "application/xml") |> get("/")
        end)

      assert body == "406 · Not Acceptable"
    end

    test "a body over the server's bound answers 413", %{conn: conn} do
      {413, headers, body} =
        assert_error_sent(413, fn ->
          conn
          |> put_req_header("accept", "text/html")
          |> put_req_header("content-type", "application/json")
          |> post("/login", oversized_json())
        end)

      assert body == "413 · Request Entity Too Large"
      assert {"content-type", "text/html; charset=utf-8"} in headers
    end

    test "404 and 500 carry their number through the same clause", %{conn: conn} do
      assert conn |> get("/no-such-page") |> html_response(404) == "404 · Not Found"
      assert ErrorView.render("500.html", %{conn: conn}) == "500 · Internal Server Error"
    end

    test "the status line follows the page's language, even before the router ran",
         %{conn: conn} do
      # The login pipeline chose the locale from the cookie.
      {403, _headers, body} =
        assert_error_sent(403, fn ->
          conn
          |> put_req_cookie("portfolixir_locale", "de")
          |> with_csrf()
          |> post("/login", %{"password" => "x"})
        end)

      assert body == "403 · Zugriff verweigert"

      # The endpoint refused the body before any pipeline ran: the page reads
      # the browser's language itself.
      {413, _headers, body} =
        assert_error_sent(413, fn ->
          conn
          |> put_req_header("accept", "text/html")
          |> put_req_header("accept-language", "de-DE,de;q=0.9,en;q=0.8")
          |> put_req_header("content-type", "application/json")
          |> post("/login", oversized_json())
        end)

      assert body == "413 · Anfrage zu groß"

      for {template, line} <- [
            {"400.html", "400 · Ungültige Anfrage"},
            {"404.html", "404 · Nicht gefunden"},
            {"406.html", "406 · Format nicht verfügbar"},
            {"500.html", "500 · Interner Fehler"}
          ] do
        de = put_req_cookie(conn, "portfolixir_locale", "de")
        assert ErrorView.render(template, %{conn: de}) == line
      end

      # No language anywhere: English.
      assert ErrorView.render("403.html", %{conn: conn}) == "403 · Forbidden"
    end
  end

  # User story (E25 S2, F68):
  # As the agent calling the JSON API,
  # I want an error the framework answers to carry the API's error shape,
  # so that an unreadable, oversized or unroutable request reads like every
  # other refusal: its status and `errors.detail`.
  #
  # Acceptance criteria:
  # - A 400 and a 413 on /api/v1 answer `{"errors": {"detail": ...}}` with
  #   their status, not a bodyless 500; an unknown /api/v1 route answers 404
  #   in the same shape.
  # - Every status renders through one JSON clause, in English whatever the
  #   request's language.
  describe "the API's error answers" do
    test "an unreadable body answers 400 in the API's error shape", %{conn: conn} do
      {400, _headers, body} =
        assert_error_sent(400, fn ->
          conn
          |> put_req_header("accept", "application/json")
          |> put_req_header("content-type", "application/json")
          |> post("/api/v1/portfolios", "{")
        end)

      assert Jason.decode!(body) == %{"errors" => %{"detail" => "Bad Request"}}
    end

    test "a body over the server's bound answers 413 in the API's error shape",
         %{conn: conn} do
      {413, _headers, body} =
        assert_error_sent(413, fn ->
          conn
          |> put_req_header("accept", "application/json")
          |> put_req_header("accept-language", "de")
          |> put_req_header("content-type", "application/json")
          |> post("/api/v1/portfolios", oversized_json())
        end)

      assert Jason.decode!(body) == %{"errors" => %{"detail" => "Request Entity Too Large"}}
    end

    test "an unknown API route answers 404 in the API's error shape", %{conn: conn} do
      response =
        conn |> put_req_header("accept", "application/json") |> get("/api/v1/no-such-route")

      assert json_response(response, 404) == %{"errors" => %{"detail" => "Not Found"}}
    end

    test "every status renders through the one JSON clause" do
      for {template, detail} <- [
            {"403.json", "Forbidden"},
            {"406.json", "Not Acceptable"},
            {"500.json", "Internal Server Error"}
          ] do
        assert ErrorView.render(template, %{}) == %{errors: %{detail: detail}}
      end
    end
  end

  # ConnTest skips CSRF protection by default; these requests keep it on.
  defp with_csrf(conn), do: Plug.Conn.put_private(conn, :plug_skip_csrf_protection, false)

  defp oversized_json, do: ~s({"x":") <> String.duplicate("a", @too_large) <> ~s("})
end
