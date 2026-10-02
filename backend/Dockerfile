FROM node:20-alpine

WORKDIR /app

RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001 -G nodejs && \
    chown -R nodejs:nodejs /app

ENV NODE_ENV=production \
    NODE_OPTIONS="--max-old-space-size=256 --no-warnings" \
    NPM_CONFIG_LOGLEVEL=silent

COPY package.json  package-lock.json ./
COPY backend/package.json  ./backend/


RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    npm ci --omit=dev && \
    npm cache clean --force


COPY /backend ./backend

# Amazon's CA bundle, so the backend can verify the RDS server certificate over TLS
ADD --chmod=644 https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem /app/certs/rds-global-bundle.pem

USER nodejs
EXPOSE 8081

ENTRYPOINT ["node", "backend/src/server.js"]

