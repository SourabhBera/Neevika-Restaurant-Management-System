const logger = require('../configs/logger');

// Request logger middleware with error handling
const requestLogger = (req, res, next) => {
  const start = Date.now();
  
  // Handle connection errors
  req.on('error', (error) => {
    const duration = Date.now() - start;
    logger.error(
      `[ERROR] ${req.method} ${req.originalUrl} - Request error after ${duration}ms: ${error.message}`
    );
  });

  res.on('error', (error) => {
    const duration = Date.now() - start;
    logger.error(
      `[ERROR] ${req.method} ${req.originalUrl} - Response error after ${duration}ms: ${error.message}`
    );
  });

  res.on('finish', () => {
    const duration = Date.now() - start;
    logger.info(
      `${req.method} ${req.originalUrl} ${res.statusCode} - ${duration}ms`
    );
  });

  res.on('close', () => {
    const duration = Date.now() - start;
    if (!res.headersSent) {
      logger.warn(
        `${req.method} ${req.originalUrl} - Connection closed prematurely after ${duration}ms`
      );
    }
  });

  next();
};

module.exports = requestLogger;
