FROM node:22-alpine

ENV PORTFOLIXIR_MCP_TRANSPORT=http \
    PORTFOLIXIR_MCP_HOST=0.0.0.0 \
    PORTFOLIXIR_MCP_PORT=4001

WORKDIR /app

COPY package.json package-lock.json tsconfig.json ./
RUN npm ci

COPY src ./src
RUN npm run build && npm prune --omit=dev

ENV NODE_ENV=production

EXPOSE 4001

CMD ["node", "dist/index.js"]
