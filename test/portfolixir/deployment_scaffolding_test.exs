defmodule Portfolixir.DeploymentScaffoldingTest do
  use ExUnit.Case, async: true

  # User story:
  # As an operator preparing the reboot foundation for staging review,
  # I want container-image deployment scaffolding based on immutable GHCR digests,
  # so that future Epics can be reviewed on staging before production promotion.
  #
  # Acceptance criteria:
  # - Runtime Compose uses PORTFOLIXIR_IMAGE and does not build or mount source code.
  # - Build image builds Dockerfile.release and prints the immutable GHCR image ref.
  # - Deploy validates a full immutable image ref before dispatching to target runners.
  # - The repo keeps exactly one build workflow and exactly one deploy workflow.
  # - Deployment docs describe digest promotion, target hosts, and Scotty/Judy responsibilities.
  test "deployment scaffolding keeps one release image build and one validated digest deploy workflow" do
    workflow_files =
      ".github/workflows"
      |> File.ls!()
      |> Enum.sort()

    assert Enum.filter(workflow_files, &String.contains?(&1, "build")) == ["build-image.yml"]
    assert Enum.filter(workflow_files, &String.starts_with?(&1, "deploy")) == ["deploy.yml"]
    refute File.exists?(".github/workflows/deploy-staging.yml")
    refute File.exists?(".github/workflows/deploy-production.yml")

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

    assert image_workflow =~ "name: Build image"
    assert image_workflow =~ "ghcr.io/peshay/portfolixir"
    assert image_workflow =~ "Dockerfile.release"
    assert image_workflow =~ "packages: write"
    assert image_workflow =~ "docker/metadata-action"
    assert image_workflow =~ "docker/build-push-action"
    assert image_workflow =~ "type=sha,prefix=sha-"
    assert image_workflow =~ "type=raw,value=main,enable=${{ github.ref == 'refs/heads/main' }}"
    assert image_workflow =~ "type=raw,value=release-${{ github.event.release.tag_name }}"
    assert image_workflow =~ "ghcr.io/peshay/portfolixir@${{ steps.build.outputs.digest }}"
    refute image_workflow =~ "ghcr.io/peshay/portfolixir:latest"
    refute image_workflow =~ "type=raw,value=latest"

    deploy_workflow = File.read!(".github/workflows/deploy.yml")

    assert deploy_workflow =~ "name: Deploy"
    assert deploy_workflow =~ "workflow_dispatch"
    assert deploy_workflow =~ "target:"
    assert deploy_workflow =~ "type: choice"
    assert deploy_workflow =~ "staging"
    assert deploy_workflow =~ "production"
    assert deploy_workflow =~ "image:"
    assert deploy_workflow =~ "^ghcr\\.io/peshay/portfolixir@sha256:[0-9a-fA-F]{64}$"

    assert deploy_workflow =~
             "runs-on: [self-hosted, Linux, X64, portfolixir, portfolixir-staging, deploy-staging]"

    assert deploy_workflow =~
             "runs-on: [self-hosted, Linux, X64, portfolixir, portfolixir-prod, deploy-prod]"

    assert deploy_workflow =~ "environment: staging"
    assert deploy_workflow =~ "environment: production"

    assert deploy_workflow =~
             "sudo /usr/local/sbin/portfolixir-deploy '${{ needs.validate.outputs.image }}'"

    refute deploy_workflow =~ "pull_request"
    refute deploy_workflow =~ "PROXMOX"
    refute deploy_workflow =~ "ssh "

    assert File.exists?("Dockerfile.release")

    deployment_docs = File.read!("docs/deployment.md")

    assert deployment_docs =~ "Build image"
    assert deployment_docs =~ "Deploy"
    assert deployment_docs =~ "Dockerfile.release"
    assert deployment_docs =~ "immutable digest"
    assert deployment_docs =~ "ghcr.io/peshay/portfolixir@sha256:<digest>"
    assert deployment_docs =~ "portfolixir-staging.home.arpa"
    assert deployment_docs =~ "portfolixir.home.arpa"

    assert deployment_docs =~ "Scotty owns LXC, DNS, reverse proxy"
    assert deployment_docs =~ "runner/deploy-agent setup"
    assert deployment_docs =~ "deploy script"
    assert deployment_docs =~ "backups, rollback"

    assert deployment_docs =~ "Judy only records, coordinates, or requests deployments"
    assert deployment_docs =~ "Production environment protection must be enabled"
  end
end
