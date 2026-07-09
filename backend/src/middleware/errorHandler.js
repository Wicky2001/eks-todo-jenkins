const pino = require('pino');
const logger = pino();

class AppError extends Error {
  constructor(message, statusCode) {
    super(message);
    this.statusCode = statusCode;
    this.isOperational = true; 
    /**
     * 🧠 WHAT IS THIS LINE DOING? (CLEANING THE NOISE FROM LOGS)
     * * Whenever an error happens, Node.js creates a hidden property called '.stack' 
     * which lists every file and line number leading up to the crash (a Stack Trace).
     * * By default, because this error is born inside this custom class constructor, 
     * the very top line of your error log would look like this:
     * ❌ 'at new AppError (C:\project\errors.js:6:5)'
     * * That line is completely useless noise. You already know you created an AppError class. 
     * You want to know which controller or service *triggered* it.
     * * Error.captureStackTrace(this, this.constructor) fixes this by telling Node.js:
     * 1. Create the standard stack trace map for this error ('this').
     * 2. Find the constructor function ('this.constructor') and completely slice off 
     * everything from that point upward.
     * * ─────────────────────────────────────────────────────────────────────────────
     * 💻 EXAMPLE:
     * * ❌ WITHOUT THIS LINE (The log is cluttered with internal plumbing code):
     * Error: Title is required
     * at new AppError (C:\project\errors.js:6:5)         <─── Useless junk line
     * at createTodo (C:\project\controllers\todo.js:8:13) <─── The actual route file
     * * 🎯 WITH THIS LINE (The junk line is sliced away automatically):
     * Error: Title is required
     * at createTodo (C:\project\controllers\todo.js:8:13) <─── Look! Perfectly clean.
     * * Now, when you open Kibana, the very first line your eyes read tells you exactly 
     * where your actual application logic failed, saving you valuable debugging time.
     */
    Error.captureStackTrace(this, this.constructor);
  }
}


function notFound(_request, response, next) {
  const error = new AppError('Resource not found', 404);
  next(error);
}

function errorHandler(error, _request, response, _next) {
 const statusCode = error.isOperational ? error.statusCode : 500;
  
 if(error.isOperational){
  return response.status(statusCode).json({
    message: error.message
  });
 }


 logger.error({
  err:error.message,
  stack:error.stack,
  statusCode:statusCode,
 },"System failure caught");

 return response.status(statusCode).json({
  message: 'Something went wrong in our end. Please try again later.'
 });


}

module.exports = {
  notFound,
  errorHandler,
  AppError
};