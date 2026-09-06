# Exact tag rather than a floating major (#761); Dependabot's docker
# ecosystem keeps it current.
FROM node:26.8.1-alpine3.24

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
