FROM node:24.12.0-alpine

WORKDIR /app

COPY package.json  package-lock.json ./
COPY migration/package.json  ./migration/

RUN npm install --workspace=migration

COPY /migration/ ./migration/

# Amazon's CA bundle, so the migration can verify the RDS server certificate over TLS
ADD --chmod=644 https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem /app/certs/rds-global-bundle.pem

CMD ["npm","run","migrate"]

