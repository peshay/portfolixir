defmodule PortfolixirWeb.LiveSessionExpiryTest do
  # async: false -- it sets the UI password and the login lifetime in the
  # application environment.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Portfolixir.Buckets.Bucket
  alias Portfolixir.Repo
  alias PortfolixirWeb.UiAuth

  @day 24 * 60 * 60

  setup do
    previous =
      Map.new([:ui_password, :session_days], &{&1, Application.fetch_env(:portfolixir, &1)})

    Application.put_env(:portfolixir, :ui_password, "synthetic-ui-password-for-h19")

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, value} -> Application.put_env(:portfolixir, key, value)
          :error -> Application.delete_env(:portfolixir, key)
        end
      end
    end)
  end

  defp authenticated_at(conn, stamp) do
    Plug.Test.init_test_session(conn, %{
      UiAuth.session_key() => true,
      UiAuth.stamp_key() => stamp,
      UiAuth.fingerprint_key() => UiAuth.password_fingerprint()
    })
  end

  # A page mounted over a login that ends two seconds later. The dead render
  # runs with no lifetime, so it does not renew the stamp; the socket then
  # mounts under a lifetime of one day.
  defp mounted_near_expiry(conn, path) do
    stamp = System.os_time(:second) - @day + 2
    Application.put_env(:portfolixir, :session_days, 0)
    rendered = conn |> authenticated_at(stamp) |> get(path)
    Application.put_env(:portfolixir, :session_days, 1)
    {:ok, view, _html} = live(rendered)
    {view, stamp}
  end

  defp wait_past(stamp) do
    remaining = (stamp + @day + 1 - System.os_time(:second)) * 1000
    if remaining > 0, do: Process.sleep(remaining + 100)
  end

  # User story (security review 2026-10-12, H19):
  # As an operator who shortens the login's lifetime for a device I may leave
  # unattended,
  # I want a page that is already open to stop answering once that lifetime
  # has run out,
  # so that the lifetime bounds what an open page can do, not only what a new
  # page can load.
  #
  # Acceptance criteria:
  # - A page mounted inside the lifetime is sent to the login once the
  #   lifetime has run out, without any event.
  # - An event sent to such a page after the lifetime is answered with the
  #   login and writes nothing.
  test "a mounted page is sent to the login at its session's expiry and writes nothing after it",
       %{conn: conn} do
    {idle, idle_stamp} = mounted_near_expiry(conn, "/buckets")
    {busy, busy_stamp} = mounted_near_expiry(build_conn(), "/buckets")

    assert has_element?(idle, "h1")
    wait_past(max(idle_stamp, busy_stamp))

    try do
      render_hook(busy, "create_bucket", %{
        "bucket" => %{"name" => "Synthetic after expiry", "dimension" => "tag"}
      })
    catch
      :exit, _reason -> :ok
    end

    assert_redirect(busy, "/login")
    assert_redirect(idle, "/login", 2_000)
    refute Repo.get_by(Bucket, name: "Synthetic after expiry")
  end
end
