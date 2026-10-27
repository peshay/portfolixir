defmodule Portfolixir.Invariants.AdvisoryFixedReleasesTest do
  use ExUnit.Case, async: true

  # User story (2026-10-12 security review triage, H28 and T-11):
  # As the operator who never reads the code,
  # I want a meta-test that fails when the money library every figure runs
  # on is not declared in mix.exs, or when the lock falls below the release
  # that fixed a published advisory on the HTTP server or the cookie signer,
  # so that Dependabot can propose the moves and a downgrade cannot reopen a
  # fixed advisory unnoticed.
  #
  # Acceptance criteria:
  # - mix.exs declares decimal with a requirement that admits the fixed
  #   release and refuses the affected one.
  # - mix.lock holds bandit, plug_crypto and decimal at or above the releases
  #   that fixed their advisories; the floors move up, never down.
  # - The test reads the manifests, not the running VM, so it holds in every
  #   environment the suite runs in.

  # The release that fixed the newest published advisory on each package, as
  # the advisory feed names it. A later advisory moves its floor up.
  @floors %{bandit: "1.14.0", plug_crypto: "2.2.1", decimal: "3.1.2"}

  test "decimal is a declared dependency whose requirement admits only fixed releases" do
    requirement =
      Enum.find_value(Mix.Project.config()[:deps], fn
        {:decimal, requirement} when is_binary(requirement) -> requirement
        {:decimal, requirement, _opts} when is_binary(requirement) -> requirement
        _other -> nil
      end)

    assert requirement, "mix.exs does not declare decimal"
    assert Version.match?("3.1.2", requirement), "the requirement refuses the fixed release"

    refute Version.match?("3.1.1", requirement),
           "the requirement still admits the affected release"
  end

  test "the lock holds every package at or above the release that fixed its advisory" do
    lock = Mix.Dep.Lock.read()

    for {package, floor} <- @floors do
      locked = locked_version(lock, package)
      assert locked, "#{package} is not in mix.lock"

      assert Version.compare(locked, floor) in [:eq, :gt],
             "#{package} is locked at #{locked}, below the fixed release #{floor}"
    end
  end

  defp locked_version(lock, package) do
    case Map.get(lock, package) do
      {:hex, ^package, version, _hash, _managers, _deps, _repo, _outer_hash} -> version
      {:hex, ^package, version, _hash, _managers, _deps, _repo} -> version
      _other -> nil
    end
  end
end
