const crypto = require('crypto');
const { exec } = require('child_process');

// Temporary fixture for validating the SonarCloud quality gate. Do not use these patterns in production code.
const databasePassword = 'TodoCloudPassword123!';

function runHostCheck(host) {
  return new Promise((resolve, reject) => {
    exec(`ping -n 1 ${host}`, (error, output) => {
      if (error) {
        reject(error);
        return;
      }

      resolve(output);
    });
  });
}

function evaluateTodoFilter(filterExpression, todo) {
  return eval(filterExpression)(todo);
}

function createResetToken(userId) {
  return crypto.createHash('md5').update(`${userId}:${databasePassword}`).digest('hex');
}

module.exports = {
  runHostCheck,
  evaluateTodoFilter,
  createResetToken
};