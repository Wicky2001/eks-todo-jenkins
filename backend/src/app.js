const express = require('express');
const cors = require('cors');
const morgan = require('morgan');
const promClient = require('prom-client');

const todoRoutes = require('./routes/todoRoutes');
const { notFound, errorHandler } = require('./middleware/errorHandler');

const app = express();
app.set("trust proxy", true);
const allowedOrigin = process.env.CORS_ORIGIN || 'http://localhost:8080';



const whitelist = process.env.CORS_ORIGINS.split(",")
  .map((origin) => origin.trim())
  .filter(Boolean);

const corsOptions = {
  credentials: true,
  origin: function (origin, callback) {
    if (!origin || whitelist.indexOf(origin) !== -1) {
      callback(null, true);
    } else {
      callback(new Error("Not Allowed by CORS"));
    }
  },
};

app.use(cors(corsOptions));
app.use(express.json());
app.use(morgan('dev'));


//####################################################################
// Promethes metrics setup
//####################################################################

// Prometheus metrics data types
const httpRequestCounter = new promClient.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'path', 'status_code'],
});

const requestDurationHistogram = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'path', 'status_code'],
  buckets: [0.1, 0.5, 1, 2, 5], // Buckets for response time in seconds
});

const requestDurationSummary = new promClient.Summary({
    name: 'http_request_duration_summary_seconds',
    help: 'Summary of the duration of HTTP requests in seconds',
    labelNames: ['method', 'path', 'status_code'],
    percentiles: [0.5, 0.9, 0.99], // Define your percentiles here
});

// Middleware to collect metrics for each request
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish',()=>{
    const duration = (Date.now() - start) / 1000; // Duration in seconds
    const {method,path} = req;
          /**
         * ⚠️ PRODUCTION ARCHITECTURAL NOTE: HIGH CARDINALITY RISK ⚠️
         * Passing raw paths (e.g., req.url) into metric labels is acceptable ONLY for 
         * static, hardcoded routes (like '/healthy' or '/metrics'). 
         * * If this application introduces dynamic paths containing unique identifiers 
         * (e.g., '/user/1001' or '/item/sku-abc'), every unique ID will force Prometheus 
         * to spin up a completely separate Time Series tracking row in memory. Under 
         * high traffic, this will cause an exponential RAM spike and crash your 
         * monitoring stack.
         * * FIX FOR DYNAMIC ROUTES: You must sanitize/normalize the path string into a 
         * structural template name (e.g., change '/user/1001' to '/user/:id') before 
         * passing it into the labels object below.
         */
    httpRequestCounter.labels({method,path,status_code:res.statusCode}).inc();
    requestDurationHistogram.labels({method,path,status_code:res.statusCode}).observe(duration);
    requestDurationSummary.labels({method,path,status_code:res.statusCode}).observe(duration);

  })

  next();
})

// Endpoint to expose Prometheus metrics
app.get('/metrics', async (req, res) => {
    res.set('Content-Type', promClient.register.contentType);
    res.end(await promClient.register.metrics());
});





app.get('/health', (_request, response) => {
  response.json({ status: 'ok' });
});

app.use('/api/todos', todoRoutes);

app.use(notFound);
app.use(errorHandler);

module.exports = app;