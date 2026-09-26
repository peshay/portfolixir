# The MCP companion's image, built in two stages (E25 S8, F58): the build
# stage installs every dependency and compiles the TypeScript; the runtime
# stage carries only the package manifest, the production modules and dist/
# -- no source, no compiler, no dev dependency, no install of its own.
#
# Exact tag rather than a floating major (#761), pinned by digest as well
# (ADR-0045 §2, E25 S2; E25 S8, F60): the digest is what gets pulled, the
# tag says which release that is. Both stages name the same one;
# Dependabot's docker ecosystem moves tag and digest together.

# --- build stage -----------------------------------------------------------
FROM node:24.21.0-alpine3.24@sha256:ebfe2f90462722a7a4de65e91990e97fe0d401c70e0e762c5b53302f905ec1c1 AS build

WORKDIR /app

# --ignore-scripts, as CI installs: no dependency's install-time lifecycle
# script (preinstall, install, postinstall) runs, because each is arbitrary
# code execution at build time and nothing in this tree needs one. The
# folder's .npmrc says the same for every npm command, the prune included.
COPY package.json package-lock.json tsconfig.json .npmrc ./
RUN npm ci --ignore-scripts

COPY src ./src
RUN npm run build && npm prune --omit=dev

# --- runtime stage ---------------------------------------------------------
FROM node:24.21.0-alpine3.24@sha256:ebfe2f90462722a7a4de65e91990e97fe0d401c70e0e762c5b53302f905ec1c1

ENV NODE_ENV=production \
    PORTFOLIXIR_MCP_TRANSPORT=http \
    PORTFOLIXIR_MCP_HOST=0.0.0.0 \
    PORTFOLIXIR_MCP_PORT=4001

WORKDIR /app

# package.json comes along because its "type": "module" is what makes Node
# load dist/ as ES modules.
COPY --from=build /app/package.json ./
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist

# The image ships a non-root `node` user (#761); the files it runs stay
# root's, so the process cannot rewrite them.
USER node

EXPOSE 4001

CMD ["node", "dist/index.js"]
