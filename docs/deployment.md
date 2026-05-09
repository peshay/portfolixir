# Deployment Scaffolding

Portfolixir reboot deployments are based on reviewed container image digests.
The digest, not a moving tag, is the reviewed and released artifact.

## Target Process

1. A branch, PR, or Epic passes CI gates.
2. The image workflow builds `Dockerfile.release`.
3. The image workflow pushes `ghcr.io/peshay/portfolixir`.
4. The workflow prints the immutable digest.
5. Staging pulls `ghcr.io/peshay/portfolixir@sha256:<digest>` through
   `deploy/compose.yml`.
6. The `/health` check passes.
7. Andreas reviews staging.
8. The accepted digest is promoted to production.
9. Production pulls the exact accepted digest through `deploy/compose.yml`.

## Runtime Compose

Local development keeps using the root `docker-compose.yml`.

Runtime deployment uses [deploy/compose.yml](../deploy/compose.yml). It uses
`PORTFOLIXIR_IMAGE`, does not build from source, does not mount the source tree,
and does not install dependencies at container startup.

Example environment files:

- [deploy/staging.env.example](../deploy/staging.env.example)
- [deploy/production.env.example](../deploy/production.env.example)

Internal Compose deployments set `DATABASE_SSL=false` by default because the app
and PostgreSQL communicate inside the Compose network.

## Release Image

[Dockerfile.release](../Dockerfile.release) builds dependencies at image build
time and runs the Phoenix release. It exposes port `4000`.

Run migrations as an explicit deployment step before starting or replacing the
app service:

```bash
docker compose --env-file deploy/staging.env -f deploy/compose.yml run --rm \
  app /app/bin/portfolixir eval "Portfolixir.Release.migrate"
```

Use the production environment file for production after staging acceptance.

## Workflow Skeletons

- `Build image` builds and pushes the GHCR release image and prints the digest.
- `Deploy staging` records a staging handoff for `portfolixir-staging.home.arpa`.
- `Deploy production` records a production handoff for `portfolixir.home.arpa`.

Production environment protection must be enabled in GitHub before the
production workflow is used. The workflow names the `production` Environment so
repository administrators can require manual approval there.

## Responsibilities

Scotty owns LXC, DNS, reverse proxy, runner/deploy-agent setup, backups, and rollback.

Judy only records, coordinates, or requests deployments. Judy does not need
Proxmox rights for this process.

## Remaining Handover Items

- Configure GitHub Environments outside the repository.
- Configure the self-hosted runner or deploy-agent outside the repository.
- Configure LXC hosts, reverse proxy, DNS, backup, and rollback outside the
  repository.
