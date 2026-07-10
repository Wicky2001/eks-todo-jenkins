"use strict";
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
  // Initialize the provider
  const provider = new NodeTracerProvider({
    resource: new Resource({
      [SemanticResourceAttributes.SERVICE_NAME]: "todo-backend", // Replace with your service name
    }),
  });


  const collector_endpoint = process.env.OTEL_EXPORTER_JAEGER_ENDPOINT;
  console.log("OTEL_EXPORTER_JAEGER_ENDPOINT:", collector_endpoint);
  const collectorOptions = {
    url: collector_endpoint, // url is optional and can be omitted - default is http://localhost:4318/v1/traces
    headers: {}, // an optional object containing custom headers to be sent with each request
    concurrencyLimit: 10, // an optional limit on pending requests
  };

  const exporter = new OTLPTraceExporter(collectorOptions);

  // Add the exporter to the provider
  provider.addSpanProcessor(new SimpleSpanProcessor(exporter));

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
