defmodule Portfolixir.DerivedConfig do
  @moduledoc """
  Switches the derived layer on for one test and puts the **configured** value
  back afterwards.

  `Application.put_env(:portfolixir, Derived, enabled?: false)` replaces the
  whole keyword list, so an `on_exit` written that way silently drops the
  `:lifetimes` the application configures — and every later test in the run
  then sees the registry defaults instead of the real activation. Only a test
  that asserts an activation notices, which is exactly why this is one helper
  rather than eight careful `on_exit`s.

  `overrides` replaces individual keys — a test that wants one analytic durable
  passes `lifetimes: [...]` and gets exactly that, unaffected by what
  `config.exs` activates.
  """

  @app :portfolixir
  @key Portfolixir.Derived

  @doc """
  Enables the derived layer for the calling test, applying `overrides`, and
  registers the restore.
  """
  @spec enable!(keyword()) :: :ok
  def enable!(overrides \\ []) do
    configured = Application.get_env(@app, @key, [])

    Application.put_env(
      @app,
      @key,
      configured |> Keyword.merge(overrides) |> Keyword.put(:enabled?, true)
    )

    ExUnit.Callbacks.on_exit(fn -> Application.put_env(@app, @key, configured) end)
    :ok
  end

  @doc "Runs `fun` with the derived layer off, restoring the configuration after."
  @spec with_layer_off((-> result)) :: result when result: term()
  def with_layer_off(fun) when is_function(fun, 0) do
    configured = Application.get_env(@app, @key, [])
    Application.put_env(@app, @key, Keyword.put(configured, :enabled?, false))

    try do
      fun.()
    after
      Application.put_env(@app, @key, configured)
    end
  end
end
