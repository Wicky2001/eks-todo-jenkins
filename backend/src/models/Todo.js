const db = require('../config/db');

const columns = 'id, title, completed, created_at AS "createdAt", updated_at AS "updatedAt"';

async function findAll() {
  const { rows } = await db.query(`SELECT ${columns} FROM todos ORDER BY created_at DESC, id DESC`);

  return rows;
}

async function create(title) {
  const { rows } = await db.query(`INSERT INTO todos (title) VALUES ($1) RETURNING ${columns}`, [title]);

  return rows[0];
}

async function toggle(id) {
  const { rows } = await db.query(
    `UPDATE todos SET completed = NOT completed, updated_at = now() WHERE id = $1 RETURNING ${columns}`,
    [id]
  );

  return rows[0] || null;
}

async function remove(id) {
  const { rows } = await db.query('DELETE FROM todos WHERE id = $1 RETURNING id', [id]);

  return rows[0] || null;
}

module.exports = {
  findAll,
  create,
  toggle,
  remove
};
