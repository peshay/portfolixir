# Exact tag rather than a floating major (#761), pinned by digest as well
# (ADR-0045 §2, E25 S2); Dependabot's docker ecosystem moves both.
FROM node:24.21.0-alpine3.24@sha256:ebfe2f90462722a7a4de65e91990e97fe0d401c70e0e762c5b53302f905ec1c1

ENV PORTFOLIXIR_MCP_TRANSPORT=http \
    PORTFOLIXIR_MCP_HOST=0.0.0.0 \
    PORTFOLIXIR_MCP_PORT=4001

WORKDIR /app

COPY package.json package-lock.json tsconfig.json ./
RUN npm ci

COPY src ./src
RUN npm run build && npm prune --omit=dev

ENV NODE_ENV=production

# The image ships a non-root `node` user (#761).
USER node

EXPOSE 4001

CMD ["node", "dist/index.js"]
