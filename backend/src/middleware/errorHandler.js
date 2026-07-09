const pino = require('pino');


class AppError extends Error {
  constructor(message, statusCode) {
    super(message);
    this.statusCode = statusCode;
    this.isOperational = true; 
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