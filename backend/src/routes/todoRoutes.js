const express = require('express');
const todoController = require('../controllers/todoController');

const router = express.Router();

router.get('/', todoController.getTodos);
router.post('/', todoController.createTodo);
router.patch('/:id/toggle', todoController.toggleTodo);
router.delete('/:id', todoController.removeTodo);

module.exports = router;