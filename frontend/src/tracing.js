import { diag, DiagConsoleLogger, DiagLogLevel } from "@opentelemetry/api";
import { WebTracerProvider } from "@opentelemetry/sdk-trace-web";
import { BatchSpanProcessor } from "@opentelemetry/sdk-trace-base";
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-http";
import { ZoneContextManager } from "@opentelemetry/context-zone";
import { ATTR_SERVICE_NAME } from "@opentelemetry/semantic-conventions";
import { registerInstrumentations } from "@opentelemetry/instrumentation";
import { getWebAutoInstrumentations } from "@opentelemetry/auto-instrumentations-web";
import { resourceFromAttributes } from "@opentelemetry/resources";

// 1. Vite environment variable check for debug logging
if (import.meta.env.MODE === "development") {
  diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.DEBUG);
}

const initTracing = () => {
  try {
    const resource = resourceFromAttributes({
      "service.name": "todo-frontend",
    });

    const collector_endpoint =
      import.meta.env.VITE_OTEL_EXPORTER_ENDPOINT ||
      "http://localhost:4318/v1/traces";

    const exporter = new OTLPTraceExporter({
      url: collector_endpoint,
    });


    const provider = new WebTracerProvider({
      resource: resource,
      spanProcessors: [new BatchSpanProcessor(exporter)],
    });


   

    // 4. Register the provider with the Web Context Manager
    provider.register({
      contextManager: new ZoneContextManager(),
    });

    // 5. Register Web Instrumentations
    registerInstrumentations({
      instrumentations: [
        getWebAutoInstrumentations({
          // This tells OTel to inject Trace IDs into requests going to your backend
          "@opentelemetry/instrumentation-fetch": {
            propagateTraceHeaderCorsUrls: [
              /.*/
            ],
          },
        }),
      ],
    });

    console.log("Frontend tracing initialized successfully");
  } catch (error) {
    console.error("Error initializing frontend tracing:", error);
  }
};

export default initTracing;
