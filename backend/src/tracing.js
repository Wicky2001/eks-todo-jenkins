"use strict";
const pino = require("pino");
const { diag, DiagConsoleLogger, DiagLogLevel } = require("@opentelemetry/api");
const { NodeTracerProvider } = require("@opentelemetry/sdk-trace-node");
const {OTLPTraceExporter} = require("@opentelemetry/exporter-trace-otlp-http");
const { registerInstrumentations } = require("@opentelemetry/instrumentation");
const { resourceFromAttributes } = require("@opentelemetry/resources");
const {SemanticResourceAttributes} = require("@opentelemetry/semantic-conventions");
const { BatchSpanProcessor } = require("@opentelemetry/sdk-trace-base");
const { HttpInstrumentation } = require("@opentelemetry/instrumentation-http");
const { PgInstrumentation } = require("@opentelemetry/instrumentation-pg");
const {ExpressInstrumentation} = require("@opentelemetry/instrumentation-express");
const { PinoInstrumentation } = require("@opentelemetry/instrumentation-pino");


const logger = pino();

if(process.env.NODE_ENV == "development") {
  diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.DEBUG);
}


try {
  const resource = resourceFromAttributes({
       "service.name": "todo-backend",
     });
  // create a exporter
  const collector_endpoint = process.env.OTEL_EXPORTER_JAEGER_ENDPOINT;

  console.log("OTEL_EXPORTER_JAEGER_ENDPOINT:", collector_endpoint);
  console.log("OTEL_LOG_LEVEL:", process.env.OTEL_LOG_LEVEL);

  const collectorOptions = {
    url: collector_endpoint, // url is optional and can be omitted - default is http://localhost:4318/v1/traces
  };

  const exporter = new OTLPTraceExporter(collectorOptions);

  // Batch: finished spans wait in a queue and are sent in groups (every 5 s, or 512 at a time),
  // instead of one network call per span.
  const provider = new NodeTracerProvider({
  resource: resource,
  spanProcessors: [
    new BatchSpanProcessor(exporter)
  ]
});

  // Initialize the provider and instrumentations
  provider.register();

  // When Kubernetes stops the pod it sends SIGTERM. Send the spans still waiting
  // in the queue before exiting, so the last requests are not lost.
  process.on("SIGTERM", () => {
    provider.shutdown().finally(() => process.exit(0));
  });

  // Automatic instrumentation for HTTP, Express, and PostgreSQL
  registerInstrumentations({
    instrumentations: [
      new HttpInstrumentation({
        applyCustomAttributesOnSpan: (span, request, response) => {
          span.setAttribute("custom-attribute", "custom-value");
        },
        // Kubernetes calls the probe endpoints every few seconds; don't make traces for them
        ignoreIncomingRequestHook: (request) =>
          request.url === "/livez" || request.url === "/readyz",
      }),
      new ExpressInstrumentation(),
      // Only trace database queries that belong to a request (so the readiness
      // "SELECT 1" and the startup connection check don't become traces of their own)
      new PgInstrumentation({ requireParentSpan: true }),
      // Adds trace_id and span_id to every pino log line written during a request,
      // so Grafana can show exactly the logs of one trace (and jump from a log to its trace).
      // Only loggers created after this point get it: server.js loads this file first.
      new PinoInstrumentation(),
    ],
  });

  console.log("Tracing initialized");
} catch (error) {
  logger.error(
    {
      err: error.message,
      stack: error.stack,
    },
    "Error initializing tracing",
  );
  console.error("Error initializing tracing:", error);
}
