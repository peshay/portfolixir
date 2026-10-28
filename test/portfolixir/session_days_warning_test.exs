defmodule Portfolixir.SessionDaysWarningTest do
  # The wiring changes the application and the OS environment, so the module
  # runs alone.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Portfolixir.RuntimeConfig

  # User story (security review 2026-10-12, H19):
  # As an operator who sets how long a UI login lasts,
  # I want a value that is not a whole number of days named at startup,
  # so that a lifetime I meant to shorten does not silently become the
  # 30-day default.
  #
  # Acceptance criteria:
  # - A fraction, a unit suffix, a negative number or any other unreadable
  #   value of PORTFOLIXIR_SESSION_DAYS gives a warning that names the
  #   variable, the value and the default it falls back to.
  # - Unset, blank, 0 or a positive whole number gives none.
  # - The application logs the warning at boot; it starts either way.
  test "a login lifetime that is not a whole number of days is named" do
    for value <- ["0.5", "1.5", "12h", "7d", "-1", "abc"] do
      assert {:warn, message} = RuntimeConfig.session_days_warning(value), value
      assert message =~ "PORTFOLIXIR_SESSION_DAYS", value
      assert message =~ inspect(value), value
      assert message =~ "30 days", value
    end

    for value <- [nil, "", "  ", "0", "7", " 90 ", 1, 0] do
      assert RuntimeConfig.session_days_warning(value) == :ok, inspect(value)
    end
  end

  test "the application logs the login-lifetime warning at boot" do
    previous_env = System.get_env("PORTFOLIXIR_SESSION_DAYS")
    previous_app = Application.fetch_env(:portfolixir, :session_days)

    on_exit(fn ->
      if previous_env,
        do: System.put_env("PORTFOLIXIR_SESSION_DAYS", previous_env),
        else: System.delete_env("PORTFOLIXIR_SESSION_DAYS")

      case previous_app do
        {:ok, value} -> Application.put_env(:portfolixir, :session_days, value)
        :error -> Application.delete_env(:portfolixir, :session_days)
      end
    end)

    Application.delete_env(:portfolixir, :session_days)
    System.put_env("PORTFOLIXIR_SESSION_DAYS", "0.5")

    log =
      capture_log([level: :warning], fn ->
        assert Portfolixir.Application.warn_if_exposed() == :ok
      end)

    assert log =~ "PORTFOLIXIR_SESSION_DAYS"
    assert log =~ ~s("0.5")
  end
end
