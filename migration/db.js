const fs = require('fs');
const { Pool } = require('pg');

function required(name) {
  const value = process.env[name];

  if (!value) {
    throw new Error(`${name} is required`);
  }

  return value;
}

function createPool() {
  const host = required('DB_HOST');
  const port = Number(process.env.DB_PORT || 5432);
  const user = required('DB_USER');

  const config = {
    host,
    port,
    user,
    database: required('DB_NAME'),
    max: 1,
    connectionTimeoutMillis: 5000
  };

  if (process.env.DB_IAM_AUTH === 'true') {
    // In the cluster there is no database password. The job gets temporary AWS keys
    // from EKS Pod Identity and signs a short-lived login token with them.
    const { Signer } = require('@aws-sdk/rds-signer');
    const signer = new Signer({
      hostname: host,
      port,
      username: user,
      region: required('AWS_REGION')
    });

    config.password = () => signer.getAuthToken();
  } else {
    config.password = process.env.DB_PASSWORD;
  }

  if (process.env.DB_SSL === 'true') {
    config.ssl = { ca: fs.readFileSync(required('DB_SSL_CA_FILE'), 'utf8') };
  }

  return new Pool(config);
}

module.exports = { createPool };
