const express = require('express');
const { getPool } = require('../config/db');

const router = express.Router();


const DB_CHECK_TIMEOUT_MS = 10000;

function withTimeout(promise, ms) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(`no answer after ${ms}ms`)), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

// since server do not start unill db connect redayness and startup prode both use same /livez endpoint
router.get('/livez', (_request, response) => {
  response.json({ status: 'ok' });
});

router.get('/readyz', async (_request, response) => {
  try {
    await withTimeout(getPool().query('SELECT 1'), DB_CHECK_TIMEOUT_MS);
    response.json({ status: 'ready', checks: { database: 'ok' } });
  } catch (error) {
    console.warn('Readiness check failed, database:', error.message);
    // Don't send error details to the caller, only which check failed.
    response.status(503).json({ status: 'not ready', checks: { database: 'down' } });
  }
});

router.get('/health', (_request, response) => {
  response.json({ status: 'ok' });
});

module.exports = router;
