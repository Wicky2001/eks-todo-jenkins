"use strict";
const pino = require("pino");
const { diag, DiagConsoleLogger, DiagLogLevel } = require("@opentelemetry/api");
const { NodeTracerProvider } = require("@opentelemetry/sdk-trace-node");
const {OTLPTraceExporter} = require("@opentelemetry/exporter-trace-otlp-http");
const { registerInstrumentations } = require("@opentelemetry/instrumentation");
const { Resource } = require("@opentelemetry/resources");
const {SemanticResourceAttributes} = require("@opentelemetry/semantic-conventions");
const { SimpleSpanProcessor } = require("@opentelemetry/sdk-trace-base");
const { HttpInstrumentation } = require("@opentelemetry/instrumentation-http");
const { MongoDBInstrumentation } = require("@opentelemetry/instrumentation-mongodb");
const {ExpressInstrumentation} = require("@opentelemetry/instrumentation-express");


const logger = pino();

if(process.env.NODE_ENV == "development") {
  diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.DEBUG);
}


try {
  const resource = Resource.resourceFromAttributes({
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

  // Add a span processor to the provider
  const provider = new NodeTracerProvider({
  resource: resource,
  spanProcessors: [
    new SimpleSpanProcessor(exporter)
  ]
});

  // Initialize the provider and instrumentations
  provider.register();

  // Automatic instrumentation for HTTP, Express, and MongoDB
  registerInstrumentations({
    instrumentations: [
      new HttpInstrumentation({
        applyCustomAttributesOnSpan: (span, request, response) => {
          span.setAttribute("custom-attribute", "custom-value");
        },
      }),
      new ExpressInstrumentation(), 
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
