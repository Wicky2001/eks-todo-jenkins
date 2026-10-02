module.exports = {
  async up(client) {
    await client.query(`
      CREATE TABLE IF NOT EXISTS todos (
        id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        title VARCHAR(160) NOT NULL,
        completed BOOLEAN NOT NULL DEFAULT false,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
      )
    `);

    await client.query('CREATE INDEX IF NOT EXISTS todos_completed_created_at_idx ON todos (completed, created_at DESC)');
  },

  async down(client) {
    await client.query('DROP TABLE IF EXISTS todos');
  }
};
