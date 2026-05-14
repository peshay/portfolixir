defmodule Portfolixir.CIFoundationTest do
  use ExUnit.Case, async: true

  # User story:
  # As a maintainer keeping the reboot foundation simple,
  # I want CI to run code coverage without deployment workflows,
  # so that the base branch proves quality without carrying staging or release machinery.
  #
  # Acceptance criteria:
  # - CI runs mix coveralls.
  # - mix coveralls is configured to run in the test environment by default.
  # - The test dependencies include excoveralls.
  # - No image build or deploy workflow remains.
  # - Release-image and runtime-deploy files are absent from the simplified foundation.
  test "ci keeps coverage while deployment automation stays out of the foundation" do
    ci_workflow = File.read!(".github/workflows/ci.yml")
    mix_file = File.read!("mix.exs")

    assert ci_workflow =~ "mix coveralls"
    assert mix_file =~ ":excoveralls"
    assert mix_file =~ "preferred_envs:"
    assert mix_file =~ ~s(coveralls: :test)

    refute File.exists?(".github/workflows/build-image.yml")
    refute File.exists?(".github/workflows/deploy.yml")
    refute File.exists?("Dockerfile.release")
    refute File.exists?("deploy")
    refute File.exists?("docs/deployment.md")
    refute File.exists?("lib/portfolixir/release.ex")
    refute File.exists?(".github/CODEOWNERS")
  end
end
