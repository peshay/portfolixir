# `assert_receive_timeout` is also the default timeout of
# `Phoenix.LiveViewTest.render_async/1` (its default argument is
# `Application.fetch_env!(:ex_unit, :assert_receive_timeout)`). At ExUnit's
# 100ms default, the async work behind a LiveView mount regularly overruns
# under `mix coveralls` instrumentation, which is what CI runs -- producing
# intermittent red runs with no defect behind them (#682 follow-on: that issue
# shipped the output artifact and seed capture precisely so the next burst
# could be inspected, and this is what the capture showed).
#
# Raising it centrally covers all 129 `render_async` call sites instead of the
# 11 that had been hand-patched with explicit timeouts. This is a *timeout*,
# not a delay: an assertion returns as soon as the async work completes, so a
# green suite is no slower. `refute_receive_timeout` is deliberately NOT
# raised -- negative assertions must stay fast.
ExUnit.start(assert_receive_timeout: 2_000)

Ecto.Adapters.SQL.Sandbox.mode(Portfolixir.Repo, :manual)
