# Deployment Scaffolding

Portfolixir reboot deployments are based on reviewed immutable digest image refs.
The digest, not a moving tag, is the reviewed and released artifact.

## Target Process

1. A branch, PR, or Epic passes CI gates.
2. The image workflow builds `Dockerfile.release`.
3. The image workflow pushes `ghcr.io/peshay/portfolixir`.
4. The workflow prints the full immutable image ref:
   `ghcr.io/peshay/portfolixir@sha256:<digest>`.
5. `Deploy` validates that full immutable image ref before dispatching to the
   selected target.
6. Staging on `portfolixir-staging.home.arpa` pulls the exact digest through
   `deploy/compose.yml`.
7. The `/health` check passes.
8. Andreas reviews staging.
9. The accepted digest is promoted to production.
10. Production on `portfolixir.home.arpa` pulls the exact accepted digest
    through `deploy/compose.yml`.

## Runtime Compose

Local development keeps using the root `docker-compose.yml`.

Runtime deployment uses [deploy/compose.yml](../deploy/compose.yml). It uses
`PORTFOLIXIR_IMAGE`, does not build from source, does not mount the source tree,
and does not install dependencies at container startup.

Example environment files:

- [deploy/staging.env.example](../deploy/staging.env.example)
- [deploy/production.env.example](../deploy/production.env.example)

Internal Compose deployments set `DATABASE_SSL=false` by default because the app
and PostgreSQL communicate inside the Compose network. Set `DATABASE_SSL=1`,
`DATABASE_SSL=true`, or `DATABASE_SSL=yes` only when the database endpoint
requires TLS.

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

## Workflows

- `Build image` builds `Dockerfile.release`, pushes
  `ghcr.io/peshay/portfolixir`, and prints the immutable image ref.
- `Deploy` accepts `target` (`staging` or `production`) and a full immutable
  image ref such as `ghcr.io/peshay/portfolixir@sha256:<digest>`.
- `Deploy` validates the image ref before running the target job.
- Staging runs on the self-hosted runner labels
  `self-hosted, Linux, X64, portfolixir, portfolixir-staging, deploy-staging`.
- Production runs on the self-hosted runner labels
  `self-hosted, Linux, X64, portfolixir, portfolixir-prod, deploy-prod`.
- The deploy command is `sudo /usr/local/sbin/portfolixir-deploy
  '<validated-image-ref>'`.

Production environment protection must be enabled in GitHub before the
production target is used. The workflow names the `production` Environment so
repository administrators can require manual approval there.

## Responsibilities

Scotty owns LXC, DNS, reverse proxy, runner/deploy-agent setup, deploy script
setup, backups, rollback, and the supporting infrastructure.

Judy only records, coordinates, or requests deployments. Judy does not need
Proxmox rights for this process.

## Remaining Handover Items

- Configure GitHub Environments outside the repository.
- Configure the self-hosted runner or deploy-agent outside the repository.
- Configure LXC hosts, reverse proxy, DNS, backup, and rollback outside the
  repository.
