module.exports = {
  async up(client) {
    await client.query(`
      INSERT INTO todos (title)
      SELECT 'Initial demo todo'
      WHERE NOT EXISTS (SELECT 1 FROM todos)
    `);
  },

  async down(client) {
    await client.query("DELETE FROM todos WHERE title = 'Initial demo todo'");
  }
};
