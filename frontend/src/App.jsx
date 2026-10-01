import { useEffect, useState } from 'react';

const API_BASE_URL = import.meta.env.VITE_API_URL || '';
const TODOS_ENDPOINT = `${API_BASE_URL}/api/todos`;

function App() {
  const [todos, setTodos] = useState([]);
  const [title, setTitle] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    void loadTodos();
  }, []);

  async function loadTodos() {
    setLoading(true);
    setError('');

    try {
      const response = await fetch(TODOS_ENDPOINT);

      if (!response.ok) {
        throw new Error('Failed to load todos');
      }

      const data = await response.json();
      setTodos(data);
    } catch (requestError) {
      setError(requestError.message || 'Unable to load todos');
    } finally {
      setLoading(false);
    }
  }

  async function handleSubmit(event) {
    event.preventDefault();

    const trimmedTitle = title.trim();

    if (!trimmedTitle) {
      return;
    }

    try {
      const response = await fetch(TODOS_ENDPOINT, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ title: trimmedTitle })
      });

      if (!response.ok) {
        throw new Error('Failed to create todo');
      }

      setTitle('');
      await loadTodos();
    } catch (requestError) {
      setError(requestError.message || 'Unable to create todo');
    }
  }

  async function toggleTodo(todoId) {
    try {
      const response = await fetch(`${TODOS_ENDPOINT}/${todoId}/toggle`, {
        method: 'PATCH'
      });

      if (!response.ok) {
        throw new Error('Failed to update todo');
      }

      await loadTodos();
    } catch (requestError) {
      setError(requestError.message || 'Unable to update todo');
    }
  }

  async function deleteTodo(todoId) {
    try {
      const response = await fetch(`${TODOS_ENDPOINT}/${todoId}`, {
        method: 'DELETE'
      });

      if (!response.ok) {
        throw new Error('Failed to delete todo');
      }

      setTodos((currentTodos) => currentTodos.filter((todo) => todo._id !== todoId));
    } catch (requestError) {
      setError(requestError.message || 'Unable to delete todo');
    }
  }

  return (
    <main className="app-shell">
      <section className="hero-card">
        <p className="eyebrow">React + Express + Mongoose + DocumentDB</p>
        <h1>Todo app scaffold for Kubernetes practice</h1>
        <p className="lede">
          A small full-stack app split into frontend, backend, database tooling, and migrations so each layer can be
          deployed independently later.
        </p>

        <form className="todo-form" onSubmit={handleSubmit}>
          <input
            type="text"
            value={title}
            placeholder="Add a new todo"
            onChange={(event) => setTitle(event.target.value)}
          />
          <button type="submit">Add todo</button>
        </form>

        {error ? <p className="status status-error">{error}</p> : null}
      </section>

      <section className="list-card">
        <div className="list-header">
          <h2>Todo list</h2>
          <button type="button" className="ghost-button" onClick={loadTodos}>
            Refresh
          </button>
        </div>

        {loading ? <p className="status">Loading todos...</p> : null}

        {!loading && todos.length === 0 ? <p className="status">No todos yet. Add your first item above.</p> : null}

        <ul className="todo-list">
          {todos.map((todo) => (
            <li key={todo._id} className={todo.completed ? 'todo-item completed' : 'todo-item'}>
              <label>
                <input type="checkbox" checked={todo.completed} onChange={() => toggleTodo(todo._id)} />
                <span>{todo.title}</span>
              </label>
              <button type="button" className="danger-button" onClick={() => deleteTodo(todo._id)}>
                Delete
              </button>
            </li>
          ))}
        </ul>
      </section>
    </main>
  );
}

export default App;