"use strict";
const { diag, DiagConsoleLogger, DiagLogLevel } = require("@opentelemetry/api");
diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.DEBUG);
const pino = require("pino");
const logger = pino();
const { NodeTracerProvider } = require("@opentelemetry/sdk-trace-node");
const {
  OTLPTraceExporter,
} = require("@opentelemetry/exporter-trace-otlp-http");
const { registerInstrumentations } = require("@opentelemetry/instrumentation");
const { Resource } = require("@opentelemetry/resources");
const {
  SemanticResourceAttributes,
} = require("@opentelemetry/semantic-conventions");
const { SimpleSpanProcessor } = require("@opentelemetry/sdk-trace-base");
const { HttpInstrumentation } = require("@opentelemetry/instrumentation-http");
const { MongoDBInstrumentation } = require("@opentelemetry/instrumentation-mongodb");
const {
  ExpressInstrumentation,
} = require("@opentelemetry/instrumentation-express");

try {
 
  // create a exporter
  const collector_endpoint = process.env.OTEL_EXPORTER_JAEGER_ENDPOINT;

  console.log("OTEL_EXPORTER_JAEGER_ENDPOINT:", collector_endpoint);
  console.log("OTEL_LOG_LEVEL:", process.env.OTEL_LOG_LEVEL);

  const collectorOptions = {
    url: collector_endpoint, // url is optional and can be omitted - default is http://localhost:4318/v1/traces
  };

  const exporter = new OTLPTraceExporter(collectorOptions);

  // Add a span processor to the provider
  const provider = new NodeTracerProvider({
  spanProcessors: [
    new SimpleSpanProcessor(exporter)
  ]
});

  // Initialize the provider and instrumentations
  provider.register();

  registerInstrumentations({
    instrumentations: [
      new HttpInstrumentation({
        applyCustomAttributesOnSpan: (span, request, response) => {
          span.setAttribute("custom-attribute", "custom-value");
        },
      }),
      new ExpressInstrumentation(), // Add this for Express.js instrumentation
      new MongoDBInstrumentation(),
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
