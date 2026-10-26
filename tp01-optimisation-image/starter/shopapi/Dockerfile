# syntax=docker/dockerfile:1.7
FROM node:20-alpine@sha256:fb4cd12c85ee03686f6af5362a0b0d56d50c58a04632e6c0fb8363f609372293 AS base
WORKDIR /app

FROM base AS dependencies
COPY package.json package-lock.json ./
RUN --mount=type=cache,id=shopapi-npm,target=/root/.npm npm ci

FROM dependencies AS test
COPY src/ ./src/
COPY test/ ./test/
RUN npm test && npm run lint

FROM base AS production-dependencies
ENV NODE_ENV=production
COPY package.json package-lock.json ./
RUN --mount=type=cache,id=shopapi-npm,target=/root/.npm npm ci --omit=dev

FROM alpine:3.23.4@sha256:5b10f432ef3da1b8d4c7eb6c487f2f5a8f096bc91145e68878dd4a5019afde11 AS runtime
ARG APP_VERSION=1.4.2
ARG GIT_SHA=local
WORKDIR /app
RUN addgroup -S -g 1000 node && adduser -S -u 1000 -G node node
COPY --from=base /usr/local/bin/node /usr/local/bin/node
COPY --from=base /usr/lib/libstdc++.so.6.0.34 /usr/lib/libstdc++.so.6.0.34
COPY --from=base /usr/lib/libgcc_s.so.1 /usr/lib/libgcc_s.so.1
RUN ln -s libstdc++.so.6.0.34 /usr/lib/libstdc++.so.6
ENV NODE_ENV=production \
    APP_VERSION=${APP_VERSION}
LABEL org.opencontainers.image.title="shopapi" \
    org.opencontainers.image.version="${APP_VERSION}" \
    org.opencontainers.image.revision="${GIT_SHA}" \
    org.opencontainers.image.source="https://github.com/christopheutp/docker_ynov_10_26"
COPY --from=production-dependencies --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node package.json ./
COPY --chown=node:node src/ ./src/
# hadolint ignore=DL3066
USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["node", "-e", "fetch('http://127.0.0.1:3000/health').then((response) => process.exit(response.ok ? 0 : 1)).catch(() => process.exit(1))"]
CMD ["node", "src/server.js"]
