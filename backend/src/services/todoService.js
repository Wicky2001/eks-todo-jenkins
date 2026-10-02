const Todo = require('../models/Todo');

const MAX_ID = 2147483647;

function parseId(value) {
  if (!/^\d+$/.test(String(value))) {
    return null;
  }

  const id = Number(value);

  return id <= MAX_ID ? id : null;
}

async function listTodos() {
  return Todo.findAll();
}

async function createTodo(title) {
  return Todo.create(title);
}

async function toggleTodo(todoId) {
  const id = parseId(todoId);

  return id === null ? null : Todo.toggle(id);
}

async function deleteTodo(todoId) {
  const id = parseId(todoId);

  return id === null ? null : Todo.remove(id);
}

module.exports = {
  listTodos,
  createTodo,
  toggleTodo,
  deleteTodo
};
