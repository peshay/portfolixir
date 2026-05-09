defmodule Portfolixir.DeploymentScaffoldingTest do
  use ExUnit.Case, async: true

  # User story:
  # As an operator preparing the reboot foundation for staging review,
  # I want container-image deployment scaffolding based on immutable GHCR digests,
  # so that future Epics can be reviewed on staging before production promotion.
  #
  # Acceptance criteria:
  # - Runtime Compose uses PORTFOLIXIR_IMAGE and does not build or mount source code.
  # - GHCR image build workflow publishes ghcr.io/peshay/portfolixir and prints the digest.
  # - Staging and production workflow skeletons use GitHub Environments and fixed LXC targets.
  # - Deployment docs describe digest promotion and Scotty/Judy responsibilities.
  test "deployment scaffolding describes GHCR digest based staging and production handoff" do
    runtime_compose = File.read!("deploy/compose.yml")

    assert runtime_compose =~ "image: ${PORTFOLIXIR_IMAGE}"
    assert runtime_compose =~ "postgres:18-alpine"
    assert runtime_compose =~ "/health"
    refute runtime_compose =~ "build:"
    refute runtime_compose =~ ".:/app"
    refute runtime_compose =~ "mix deps.get"

    staging_env = File.read!("deploy/staging.env.example")
    production_env = File.read!("deploy/production.env.example")

    assert staging_env =~ "PORTFOLIXIR_IMAGE=ghcr.io/peshay/portfolixir@sha256:<digest>"
    assert staging_env =~ "PHX_HOST=portfolixir-staging.home.arpa"
    assert staging_env =~ "DATABASE_SSL=false"
    assert production_env =~ "PORTFOLIXIR_IMAGE=ghcr.io/peshay/portfolixir@sha256:<digest>"
    assert production_env =~ "PHX_HOST=portfolixir.home.arpa"
    assert production_env =~ "DATABASE_SSL=false"

    image_workflow = File.read!(".github/workflows/build-image.yml")

    assert image_workflow =~ "ghcr.io/peshay/portfolixir"
    assert image_workflow =~ "Dockerfile.release"
    assert image_workflow =~ "digest"
    refute image_workflow =~ "ghcr.io/peshay/portfolixir:latest"
    refute image_workflow =~ "type=raw,value=latest"

    staging_workflow = File.read!(".github/workflows/deploy-staging.yml")
    production_workflow = File.read!(".github/workflows/deploy-production.yml")

    assert staging_workflow =~ "environment: staging"
    assert staging_workflow =~ "portfolixir-staging.home.arpa"
    assert production_workflow =~ "environment: production"
    assert production_workflow =~ "portfolixir.home.arpa"

    assert File.exists?("Dockerfile.release")

    deployment_docs = File.read!("docs/deployment.md")

    assert deployment_docs =~ "immutable digest"

    assert deployment_docs =~
             "Scotty owns LXC, DNS, reverse proxy, runner/deploy-agent setup, backups, and rollback"

    assert deployment_docs =~ "Judy only records, coordinates, or requests deployments"
    assert deployment_docs =~ "Production environment protection must be enabled"
  end
end
