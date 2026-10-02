const todoService = require('../services/todoService');
const {AppError} = require('../middleware/errorHandler');
const pino = require('pino');
const logger = pino();

async function getTodos(_request, response, next) {
  try {
    const todos = await todoService.listTodos();
    response.json(todos);
    logger.info({ todos:todos }, 'Todos retrieved successfully');
  } catch (error) {
    next(error);
  }
}

async function createTodo(request, response, next) {
  try {
    const title = request.body?.title?.trim();

    if (!title) {
      throw new AppError('Title is required',400);
    }

    if (title.length > 160) {
      throw new AppError('Title must be 160 characters or less',400);
    }

    const todo = await todoService.createTodo(title);
    logger.info({ todo:todo }, 'Todo created successfully');
    response.status(201).json(todo);
  } catch (error) {
    next(error);
  }
}

async function toggleTodo(request, response, next) {
  try {
    const todo = await todoService.toggleTodo(request.params.id);

    if (!todo) {
      throw new AppError('Todo not found',404);
    }

    response.json(todo);
  } catch (error) {
    next(error);
  }
}

async function removeTodo(request, response, next) {
  try {
    const removed = await todoService.deleteTodo(request.params.id);

    if (!removed) {
      throw new AppError('Todo not found',404);
    }

    logger.info({ todoId:request.params.id }, 'Todo removed successfully');
    response.status(204).send();
  } catch (error) {
    next(error);
  }
}

module.exports = {
  getTodos,
  createTodo,
  toggleTodo,
  removeTodo
};